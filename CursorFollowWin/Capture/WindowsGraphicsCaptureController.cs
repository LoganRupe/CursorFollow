using Microsoft.Extensions.Logging;
using Microsoft.Graphics.Canvas;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Windows.Foundation.Metadata;
using Windows.Graphics;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.Imaging;
using Windows.Security.Authorization.AppCapabilityAccess;
using WinRT;

namespace CursorFollowWin;

public sealed class WindowsGraphicsCaptureController : IDisposable
{
    /// <summary>Forwards <see cref="CaptureConstants.OutputWindowTitle"/> so existing call sites that
    /// reference the controller keep compiling; the single source of truth lives in Shared.</summary>
    public const string OutputWindowTitle = CaptureConstants.OutputWindowTitle;

    private static readonly Guid GraphicsCaptureItemInterfaceId = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");

    private readonly CanvasDevice _device = new();
    private Direct3D11CaptureFramePool? _framePool;
    private GraphicsCaptureSession? _session;
    private GraphicsCaptureItem? _item;
    private SizeInt32 _lastContentSize;
    private string _targetName = "Selected target";
    private long _sequence;
    private long _droppedFrames;
    private int _frameProcessing;
    private bool _programmaticAccessGranted;
    private bool _disposed;

    // Capture-quality knobs. Defaults match the "Balanced" setting so behavior is correct
    // even if ApplyQuality is never called.
    private int _frameBufferCount = 2;
    private TimeSpan _minFrameInterval = TimeSpan.FromSeconds(1.0 / 60);
    private DateTimeOffset _lastAcceptedFrame = DateTimeOffset.MinValue;
    private CaptureQuality _quality = CaptureQuality.Balanced;

    public event Action<CapturedFrame>? FrameReady;

    public event Action<string>? CaptureStopped;

    public event Action<Exception>? CaptureFailed;

    public async Task<bool> SelectTargetAsync(IntPtr ownerWindow)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        if (!GraphicsCaptureSession.IsSupported())
        {
            throw new InvalidOperationException("Windows Graphics Capture is not supported on this system.");
        }

        var picker = new GraphicsCapturePicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, ownerWindow);

        var item = await picker.PickSingleItemAsync();
        if (item is null)
        {
            return false;
        }

        if (string.Equals(item.DisplayName, OutputWindowTitle, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("CursorFollow Output cannot be selected as its own capture target.");
        }

        _targetName = item.DisplayName;
        Start(item);
        return true;
    }

    public async Task StartWindowCaptureAsync(TrackedWindow window)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        if (!GraphicsCaptureSession.IsSupported())
        {
            throw new InvalidOperationException("Windows Graphics Capture is not supported on this system.");
        }

        await EnsureProgrammaticAccessAsync();

        _targetName = window.DisplayName;
        Start(CreateItemForWindow(window.Handle));
    }

    public void Stop()
    {
        StopCapture(raiseStopped: false);
    }

    /// <summary>
    /// Applies a capture-quality preset. Buffer depth and the frame-rate cap change to trade
    /// latency against CPU load. If a buffer-depth change is needed while a session is live,
    /// the session is restarted on the same target.
    /// </summary>
    public void ApplyQuality(string quality)
    {
        var parsed = ParseQuality(quality);
        var (bufferCount, minInterval) = QualitySettings(parsed);
        var bufferChanged = bufferCount != _frameBufferCount;

        _quality = parsed;
        _frameBufferCount = bufferCount;
        _minFrameInterval = minInterval;

        if (bufferChanged && _item is { } current)
        {
            Start(current);
        }
    }

    private static CaptureQuality ParseQuality(string quality) => quality switch
    {
        "Performance" => CaptureQuality.Performance,
        "Low-Latency" => CaptureQuality.LowLatency,
        _ => CaptureQuality.Balanced,
    };

    private static (int BufferCount, TimeSpan MinInterval) QualitySettings(CaptureQuality quality) => quality switch
    {
        // Low-latency: shallow buffer, no frame-rate cap (process every frame the source emits).
        CaptureQuality.LowLatency => (2, TimeSpan.Zero),
        // Performance: deeper buffer for smoothness, capped at 30 fps to reduce CPU/GPU load.
        CaptureQuality.Performance => (3, TimeSpan.FromSeconds(1.0 / 30)),
        // Balanced: shallow buffer, capped at 60 fps.
        _ => (2, TimeSpan.FromSeconds(1.0 / 60)),
    };

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        StopCapture(raiseStopped: false);
        _device.Dispose();
    }

    private void Start(GraphicsCaptureItem item)
    {
        StopCapture(raiseStopped: false);

        _item = item;
        _lastContentSize = EnsureValidSize(item.Size);
        _sequence = 0;
        _droppedFrames = 0;
        _lastAcceptedFrame = DateTimeOffset.MinValue;

        _framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            _device,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            _frameBufferCount,
            _lastContentSize);

        _session = _framePool.CreateCaptureSession(item);

        if (ApiInformation.IsPropertyPresent(typeof(GraphicsCaptureSession).FullName, nameof(GraphicsCaptureSession.IsCursorCaptureEnabled)))
        {
            _session.IsCursorCaptureEnabled = true;
        }

        item.Closed += Item_Closed;
        _framePool.FrameArrived += FramePool_FrameArrived;
        _session.StartCapture();

        AppLog.Capture.LogInformation(
            "Capture started for '{Target}' at {Width}x{Height} (quality {Quality}, buffers {Buffers}).",
            _targetName,
            _lastContentSize.Width,
            _lastContentSize.Height,
            _quality,
            _frameBufferCount);
    }

    private async void FramePool_FrameArrived(Direct3D11CaptureFramePool sender, object args)
    {
        if (Interlocked.Exchange(ref _frameProcessing, 1) == 1)
        {
            Interlocked.Increment(ref _droppedFrames);
            return;
        }

        try
        {
            var timestamp = DateTimeOffset.Now;
            var copyTimer = Stopwatch.StartNew();
            using var frame = sender.TryGetNextFrame();
            var contentSize = EnsureValidSize(frame.ContentSize);

            if (contentSize.Width != _lastContentSize.Width || contentSize.Height != _lastContentSize.Height)
            {
                _lastContentSize = contentSize;
                sender.Recreate(_device, DirectXPixelFormat.B8G8R8A8UIntNormalized, _frameBufferCount, contentSize);
            }

            // Frame-rate cap for Balanced/Performance: drain the frame to keep the pool moving
            // but skip the expensive copy/present. Not counted as a dropped frame, since this is
            // intentional pacing rather than the renderer falling behind.
            if (_minFrameInterval > TimeSpan.Zero && timestamp - _lastAcceptedFrame < _minFrameInterval)
            {
                return;
            }

            _lastAcceptedFrame = timestamp;
            var bitmap = await SoftwareBitmap.CreateCopyFromSurfaceAsync(frame.Surface);
            copyTimer.Stop();
            var displayBitmap = EnsureDisplayBitmap(bitmap);
            var sequence = Interlocked.Increment(ref _sequence);
            FrameReady?.Invoke(new CapturedFrame(displayBitmap, contentSize, sequence, timestamp, _targetName, copyTimer.Elapsed, Interlocked.Read(ref _droppedFrames)));
        }
        catch (Exception ex)
        {
            AppLog.Capture.LogError(ex, "Frame processing failed for '{Target}'.", _targetName);
            CaptureFailed?.Invoke(ex);
        }
        finally
        {
            Interlocked.Exchange(ref _frameProcessing, 0);
        }
    }

    private void Item_Closed(GraphicsCaptureItem sender, object args)
    {
        StopCapture(raiseStopped: true, reason: "The selected target closed or stopped sharing frames.");
    }

    private void StopCapture(bool raiseStopped, string reason = "Capture stopped")
    {
        if (_item is not null)
        {
            _item.Closed -= Item_Closed;
            _item = null;
        }

        if (_framePool is not null)
        {
            _framePool.FrameArrived -= FramePool_FrameArrived;
            _framePool.Dispose();
            _framePool = null;
        }

        _session?.Dispose();
        _session = null;
        Interlocked.Exchange(ref _frameProcessing, 0);

        if (raiseStopped)
        {
            AppLog.Capture.LogInformation("Capture stopped: {Reason}", reason);
            CaptureStopped?.Invoke(reason);
        }
    }

    private static SoftwareBitmap EnsureDisplayBitmap(SoftwareBitmap bitmap)
    {
        if (bitmap.BitmapPixelFormat == BitmapPixelFormat.Bgra8 && bitmap.BitmapAlphaMode == BitmapAlphaMode.Premultiplied)
        {
            return bitmap;
        }

        var converted = SoftwareBitmap.Convert(bitmap, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
        bitmap.Dispose();
        return converted;
    }

    private static SizeInt32 EnsureValidSize(SizeInt32 size)
    {
        return new SizeInt32(Math.Max(1, size.Width), Math.Max(1, size.Height));
    }

    private async Task EnsureProgrammaticAccessAsync()
    {
        if (_programmaticAccessGranted)
        {
            return;
        }

        var access = await GraphicsCaptureAccess.RequestAccessAsync(GraphicsCaptureAccessKind.Programmatic);
        if (access != AppCapabilityAccessStatus.Allowed)
        {
            AppLog.Capture.LogWarning("Programmatic capture access denied ({Access}).", access);
            throw new InvalidOperationException($"Programmatic window capture was not allowed ({access}). Use Select target if Windows blocks automatic capture for this app session.");
        }

        _programmaticAccessGranted = true;
    }

    private static GraphicsCaptureItem CreateItemForWindow(IntPtr windowHandle)
    {
        var className = IntPtr.Zero;
        var factoryPointer = IntPtr.Zero;
        var itemPointer = IntPtr.Zero;

        try
        {
            Marshal.ThrowExceptionForHR(WindowsCreateString(
                "Windows.Graphics.Capture.GraphicsCaptureItem",
                "Windows.Graphics.Capture.GraphicsCaptureItem".Length,
                out className));

            var interopGuid = typeof(IGraphicsCaptureItemInterop).GUID;
            Marshal.ThrowExceptionForHR(RoGetActivationFactory(className, ref interopGuid, out factoryPointer));

            var interop = (IGraphicsCaptureItemInterop)Marshal.GetObjectForIUnknown(factoryPointer);
            var itemGuid = GraphicsCaptureItemInterfaceId;
            Marshal.ThrowExceptionForHR(interop.CreateForWindow(windowHandle, ref itemGuid, out itemPointer));

            return MarshalInterface<GraphicsCaptureItem>.FromAbi(itemPointer);
        }
        finally
        {
            if (itemPointer != IntPtr.Zero)
            {
                Marshal.Release(itemPointer);
            }

            if (factoryPointer != IntPtr.Zero)
            {
                Marshal.Release(factoryPointer);
            }

            if (className != IntPtr.Zero)
            {
                WindowsDeleteString(className);
            }
        }
    }

    [ComImport]
    [System.Runtime.InteropServices.Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IGraphicsCaptureItemInterop
    {
        [PreserveSig]
        int CreateForWindow(IntPtr window, ref Guid iid, out IntPtr result);

        [PreserveSig]
        int CreateForMonitor(IntPtr monitor, ref Guid iid, out IntPtr result);
    }

    [DllImport("combase.dll", ExactSpelling = true)]
    private static extern int RoGetActivationFactory(IntPtr activatableClassId, ref Guid iid, out IntPtr factory);

    [DllImport("combase.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    private static extern int WindowsCreateString(string sourceString, int length, out IntPtr hstring);

    [DllImport("combase.dll", ExactSpelling = true)]
    private static extern int WindowsDeleteString(IntPtr hstring);
}

internal enum CaptureQuality
{
    Balanced,
    Performance,
    LowLatency,
}

public sealed record CapturedFrame(
    SoftwareBitmap Bitmap,
    SizeInt32 ContentSize,
    long Sequence,
    DateTimeOffset Timestamp,
    string TargetName,
    TimeSpan CopyDuration,
    long DroppedFrames);