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

namespace CursorFollowWin_App;

internal sealed class WindowsGraphicsCaptureController : IDisposable
{
    public const string OutputWindowTitle = "CursorFollow Output";

    private const int FrameBufferCount = 2;
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

        _framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            _device,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            FrameBufferCount,
            _lastContentSize);

        _session = _framePool.CreateCaptureSession(item);

        if (ApiInformation.IsPropertyPresent(typeof(GraphicsCaptureSession).FullName, nameof(GraphicsCaptureSession.IsCursorCaptureEnabled)))
        {
            _session.IsCursorCaptureEnabled = true;
        }

        item.Closed += Item_Closed;
        _framePool.FrameArrived += FramePool_FrameArrived;
        _session.StartCapture();
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
                sender.Recreate(_device, DirectXPixelFormat.B8G8R8A8UIntNormalized, FrameBufferCount, contentSize);
            }

            var bitmap = await SoftwareBitmap.CreateCopyFromSurfaceAsync(frame.Surface);
            copyTimer.Stop();
            var displayBitmap = EnsureDisplayBitmap(bitmap);
            var sequence = Interlocked.Increment(ref _sequence);
            FrameReady?.Invoke(new CapturedFrame(displayBitmap, contentSize, sequence, timestamp, _targetName, copyTimer.Elapsed, Interlocked.Read(ref _droppedFrames)));
        }
        catch (Exception ex)
        {
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

internal sealed record CapturedFrame(
    SoftwareBitmap Bitmap,
    SizeInt32 ContentSize,
    long Sequence,
    DateTimeOffset Timestamp,
    string TargetName,
    TimeSpan CopyDuration,
    long DroppedFrames);