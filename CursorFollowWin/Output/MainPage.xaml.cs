using Microsoft.Extensions.Logging;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using System.Globalization;

namespace CursorFollowWin;

public sealed partial class MainPage : Page
{
    private const int DefaultContentWidth = 1280;
    private const int DefaultContentHeight = 720;

    private readonly WindowsGraphicsCaptureController _captureController = new();
    private IntPtr _windowHandle;
    private OutputState _currentState = OutputState.Idle;
    private string _status = "Waiting for target selection";
    private string _targetName = "Manual target picker";
    private DateTimeOffset _lastPresentedAt;
    private DateTimeOffset _lastTelemetryLoggedAt;
    private double _smoothedFramesPerSecond;
    private double _smoothedRenderLatencyMs;
    private int _contentWidth = DefaultContentWidth;
    private int _contentHeight = DefaultContentHeight;

    public MainPage()
    {
        InitializeComponent();

        _captureController.FrameReady += CaptureController_FrameReady;
        _captureController.CaptureStopped += CaptureController_CaptureStopped;
        _captureController.CaptureFailed += CaptureController_CaptureFailed;

        UpdateState(OutputState.Idle);
    }

    public event EventHandler? OutputStateChanged;

    /// <summary>Raised with the captured content size so the window can match its aspect ratio.</summary>
    public event Action<int, int>? ContentSizeChanged;

    public bool IsCapturing => _currentState == OutputState.Live;

    public string Status => _status;

    public string TargetName => _targetName;

    public OutputPipelineSnapshot PipelineSnapshot { get; private set; } = OutputPipelineSnapshot.Empty;

    public void InitializeWindowHandle(IntPtr windowHandle)
    {
        _windowHandle = windowHandle;
    }

    public async Task SelectTargetAsync()
    {
        if (_windowHandle == IntPtr.Zero)
        {
            UpdateState(OutputState.Error, "Output window handle is not available.");
            return;
        }

        SetStatus("Opening Windows capture picker");

        try
        {
            var started = await _captureController.SelectTargetAsync(_windowHandle);
            UpdateState(started ? OutputState.Live : OutputState.Idle);
        }
        catch (Exception ex)
        {
            UpdateState(OutputState.Error, ex.Message);
        }
    }

    public async Task<bool> CaptureWindowAsync(TrackedWindow window)
    {
        try
        {
            await _captureController.StartWindowCaptureAsync(window);
            _targetName = window.DisplayName;
            UpdateState(OutputState.Live);
            return true;
        }
        catch (Exception ex)
        {
            UpdateState(OutputState.Error, ex.Message);
            return false;
        }
    }

    public void StopCapture()
    {
        _captureController.Stop();
        CaptureImage.Source = null;
        ResetContentSize();
        UpdateState(OutputState.Idle);
    }

    public void ApplyCaptureQuality(string quality)
    {
        _captureController.ApplyQuality(quality);
    }

    public void ApplyOutputScaleMode(string scaleMode)
    {
        OutputViewbox.Stretch = scaleMode switch
        {
            "Fill" => Stretch.UniformToFill,
            "Actual" => Stretch.None,
            _ => Stretch.Uniform, // Fit
        };
    }

    public void DisposeCapture()
    {
        _captureController.Dispose();
    }

    private void UpdateContentSize(int width, int height)
    {
        FrameSurface.Width = width;
        FrameSurface.Height = height;

        if (width == _contentWidth && height == _contentHeight)
        {
            return;
        }

        _contentWidth = width;
        _contentHeight = height;
        ContentSizeChanged?.Invoke(width, height);
    }

    private void ResetContentSize() => UpdateContentSize(DefaultContentWidth, DefaultContentHeight);

    private void CaptureController_FrameReady(CapturedFrame frame)
    {
        var queued = DispatcherQueue.TryEnqueue(async () =>
        {
            using var bitmap = frame.Bitmap;
            var source = new SoftwareBitmapSource();
            await source.SetBitmapAsync(bitmap);

            CaptureImage.Source = source;
            UpdateContentSize(
                Math.Max(1, frame.ContentSize.Width),
                Math.Max(1, frame.ContentSize.Height));
            _targetName = frame.TargetName;
            _currentState = OutputState.Live;
            UpdatePipelineSnapshot(frame);
            SetStatus(FormatLiveStatus(frame));
        });

        if (!queued)
        {
            frame.Bitmap.Dispose();
        }
    }

    private void CaptureController_CaptureStopped(string reason)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            UpdateState(OutputState.Error, reason);
        });
    }

    private void CaptureController_CaptureFailed(Exception exception)
    {
        DispatcherQueue.TryEnqueue(() => UpdateState(OutputState.Error, exception.Message));
    }

    private void UpdateState(OutputState state, string? detail = null)
    {
        _currentState = state;

        switch (state)
        {
            case OutputState.Live:
                SetStatus("Waiting for first captured frame");
                break;

            case OutputState.Idle:
                _targetName = "Manual target picker";
                SetStatus(detail ?? "Waiting for target selection");
                break;

            default:
                AppLog.Output.LogWarning("Output entered fallback/error state: {Detail}", detail ?? "unspecified");
                SetStatus(detail ?? "Error / fallback output");
                break;
        }
    }

    private void SetStatus(string status)
    {
        _status = status;
        OutputStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void UpdatePipelineSnapshot(CapturedFrame frame)
    {
        var presentedAt = DateTimeOffset.Now;
        var renderLatencyMs = Math.Max(0, (presentedAt - frame.Timestamp).TotalMilliseconds);

        if (_lastPresentedAt != default)
        {
            var frameIntervalMs = Math.Max(1, (presentedAt - _lastPresentedAt).TotalMilliseconds);
            var instantFramesPerSecond = 1000 / frameIntervalMs;
            _smoothedFramesPerSecond = _smoothedFramesPerSecond <= 0
                ? instantFramesPerSecond
                : (_smoothedFramesPerSecond * 0.85) + (instantFramesPerSecond * 0.15);
        }

        _smoothedRenderLatencyMs = _smoothedRenderLatencyMs <= 0
            ? renderLatencyMs
            : (_smoothedRenderLatencyMs * 0.85) + (renderLatencyMs * 0.15);
        _lastPresentedAt = presentedAt;

        PipelineSnapshot = new OutputPipelineSnapshot(
            frame.Sequence,
            frame.ContentSize.Width,
            frame.ContentSize.Height,
            _smoothedFramesPerSecond,
            frame.CopyDuration.TotalMilliseconds,
            _smoothedRenderLatencyMs,
            frame.DroppedFrames,
            frame.TargetName);

        // Throttled telemetry so capture-to-output latency, fps, and dropped frames are recoverable
        // from the logs for verification runs (the UI-only status line is not persisted).
        if (presentedAt - _lastTelemetryLoggedAt >= TimeSpan.FromSeconds(2))
        {
            _lastTelemetryLoggedAt = presentedAt;
            AppLog.Output.LogInformation(
                "Telemetry: {Width}x{Height} {Fps:0.0} fps, copy {Copy:0.0} ms, render {Render:0.0} ms, dropped {Dropped}, seq {Seq}",
                PipelineSnapshot.Width,
                PipelineSnapshot.Height,
                PipelineSnapshot.FramesPerSecond,
                PipelineSnapshot.CopyMilliseconds,
                PipelineSnapshot.RenderLatencyMilliseconds,
                PipelineSnapshot.DroppedFrames,
                PipelineSnapshot.Sequence);
        }
    }

    private string FormatLiveStatus(CapturedFrame frame)
    {
        var snapshot = PipelineSnapshot;
        return string.Create(
            CultureInfo.InvariantCulture,
            $"Live | {snapshot.Width}x{snapshot.Height} | {snapshot.FramesPerSecond:0.0} fps | copy {snapshot.CopyMilliseconds:0.0} ms | render {snapshot.RenderLatencyMilliseconds:0.0} ms | dropped {snapshot.DroppedFrames} | {frame.TargetName}");
    }

    private enum OutputState
    {
        Idle,
        Error,
        Live,
    }
}

public sealed record OutputPipelineSnapshot(
    long Sequence,
    int Width,
    int Height,
    double FramesPerSecond,
    double CopyMilliseconds,
    double RenderLatencyMilliseconds,
    long DroppedFrames,
    string TargetName)
{
    public static OutputPipelineSnapshot Empty { get; } = new(0, 0, 0, 0, 0, 0, 0, "No target");
}
