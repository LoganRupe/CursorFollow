using Microsoft.Extensions.Logging;
using Microsoft.Graphics.Canvas;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using Windows.Graphics.DirectX.Direct3D11;

namespace CursorFollowWin;

public sealed partial class MainPage : Page
{
    private const int DefaultContentWidth = 1280;
    private const int DefaultContentHeight = 720;
    private const string DefaultTargetName = "Manual target picker";

    // One Win2D device shared by the capture frame pool and the output swap chain so captured
    // surfaces render with no cross-device copy. Owned here; the controller does not dispose it.
    private readonly CanvasDevice _device = new();
    private readonly WindowsGraphicsCaptureController _captureController;
    private readonly SwapChainRenderer _renderer;
    private IntPtr _windowHandle;
    private OutputState _currentState = OutputState.Idle;
    private string _status = "Waiting for target selection";
    private string _targetName = DefaultTargetName;
    private DateTimeOffset _lastPresentedAt;
    private DateTimeOffset _lastTelemetryLoggedAt;
    private double _smoothedFramesPerSecond;
    private double _smoothedRenderLatencyMs;
    private int _contentWidth = DefaultContentWidth;
    private int _contentHeight = DefaultContentHeight;
    private bool _showResolution;
    private bool _showFrameCount;

    public MainPage()
    {
        InitializeComponent();

        _captureController = new WindowsGraphicsCaptureController(_device);
        _renderer = new SwapChainRenderer(SwapPanel, _device);

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
        _renderer.Clear();
        ResetContentSize();
        PipelineSnapshot = OutputPipelineSnapshot.Empty;
        UpdateMetricsOverlay();

        // A stop after a live capture is a pause: keep the last target name so the overlay can offer
        // to resume it. A stop before anything was ever captured falls back to the idle "no target" card.
        UpdateState(HasResumableTarget ? OutputState.Paused : OutputState.Idle);
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

    public void ApplyMetricsOverlay(bool showResolution, bool showFrameCount)
    {
        _showResolution = showResolution;
        _showFrameCount = showFrameCount;
        UpdateMetricsOverlay();
    }

    // Builds the resolution / fps overlay from the latest pipeline snapshot. Hidden entirely when
    // neither metric is enabled (or before the first frame), matching the macOS output overlay.
    private void UpdateMetricsOverlay()
    {
        var snapshot = PipelineSnapshot;
        var lines = new List<string>(2);

        if (_showResolution && snapshot.Width > 0 && snapshot.Height > 0)
        {
            lines.Add(string.Create(CultureInfo.InvariantCulture, $"{snapshot.Width} x {snapshot.Height}"));
        }

        if (_showFrameCount)
        {
            lines.Add(string.Create(CultureInfo.InvariantCulture, $"{snapshot.FramesPerSecond:0} fps"));
        }

        if (lines.Count == 0)
        {
            MetricsOverlay.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
            return;
        }

        MetricsText.Text = string.Join(Environment.NewLine, lines);
        MetricsOverlay.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
    }

    public void DisposeCapture()
    {
        _captureController.Dispose();
        _renderer.Dispose();
        _device.Dispose();
    }

    private void UpdateContentSize(int width, int height)
    {
        SwapPanel.Width = width;
        SwapPanel.Height = height;

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
        // Render the live GPU surface immediately on the capture thread — it is valid only for the
        // duration of this callback. No CPU copy; the swap chain presents the surface directly.
        double presentMs;
        try
        {
            var timer = Stopwatch.StartNew();
            _renderer.Render(frame.Surface, frame.ContentSize);
            presentMs = timer.Elapsed.TotalMilliseconds;
        }
        catch (Exception ex)
        {
            DispatcherQueue.TryEnqueue(() => UpdateState(OutputState.Error, $"GPU render failed: {ex.Message}"));
            return;
        }

        var presentedAt = DateTimeOffset.Now;

        // Status text and telemetry touch XAML and shared state, so marshal them to the UI thread.
        DispatcherQueue.TryEnqueue(() =>
        {
            UpdateContentSize(
                Math.Max(1, frame.ContentSize.Width),
                Math.Max(1, frame.ContentSize.Height));
            _targetName = frame.TargetName;
            _currentState = OutputState.Live;
            UpdatePipelineSnapshot(frame, presentedAt, presentMs);
            UpdateMetricsOverlay();
            SetStatus(FormatLiveStatus(frame));
        });
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

    private bool HasResumableTarget =>
        !string.IsNullOrEmpty(_targetName) && _targetName != DefaultTargetName;

    private void UpdateState(OutputState state, string? detail = null)
    {
        _currentState = state;

        switch (state)
        {
            case OutputState.Live:
                SetStatus("Waiting for first captured frame");
                break;

            case OutputState.Idle:
                _targetName = DefaultTargetName;
                SetStatus(detail ?? "Waiting for target selection");
                break;

            case OutputState.Paused:
                SetStatus(detail ?? "Output paused");
                break;

            default:
                AppLog.Output.LogWarning("Output entered fallback/error state: {Detail}", detail ?? "unspecified");
                SetStatus(detail ?? "Error / fallback output");
                break;
        }

        UpdateFallbackOverlay();
    }

    // Centered card shown over the (black) output surface whenever there is nothing live to display.
    // Hidden entirely while capturing; otherwise mirrors the macOS output window's idle/paused/error cards.
    private void UpdateFallbackOverlay()
    {
        if (_currentState == OutputState.Live)
        {
            FallbackOverlay.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
            return;
        }

        string title;
        string message;
        var icon = _currentState switch
        {
            OutputState.Paused => FallbackIcon.Paused,
            OutputState.Error => FallbackIcon.Error,
            _ => FallbackIcon.NoTarget,
        };

        switch (_currentState)
        {
            case OutputState.Paused:
                title = "Output Paused";
                message = HasResumableTarget
                    ? string.Create(CultureInfo.InvariantCulture, $"Ready to resume {_targetName}.")
                    : "Start capture when you are ready.";
                break;

            case OutputState.Error:
                title = "Output Unavailable";
                message = _status;
                break;

            default:
                title = "No Target Selected";
                message = "Choose a window in CursorFollow to start sharing.";
                break;
        }

        NoTargetIcon.Visibility = ToVisibility(icon == FallbackIcon.NoTarget);
        PausedIcon.Visibility = ToVisibility(icon == FallbackIcon.Paused);
        ErrorIcon.Visibility = ToVisibility(icon == FallbackIcon.Error);

        FallbackTitle.Text = title;
        FallbackMessage.Text = message;
        FallbackOverlay.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
    }

    private static Microsoft.UI.Xaml.Visibility ToVisibility(bool visible) =>
        visible ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;

    private void SetStatus(string status)
    {
        _status = status;
        OutputStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void UpdatePipelineSnapshot(CapturedFrame frame, DateTimeOffset presentedAt, double presentMs)
    {
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
            presentMs,
            _smoothedRenderLatencyMs,
            frame.DroppedFrames,
            frame.TargetName);

        // Throttled telemetry so capture-to-output latency, fps, and dropped frames are recoverable
        // from the logs for verification runs (the UI-only status line is not persisted).
        if (presentedAt - _lastTelemetryLoggedAt >= TimeSpan.FromSeconds(2))
        {
            _lastTelemetryLoggedAt = presentedAt;
            AppLog.Output.LogInformation(
                "Telemetry: {Width}x{Height} {Fps:0.0} fps, present {Present:0.0} ms, render {Render:0.0} ms, dropped {Dropped}, seq {Seq}",
                PipelineSnapshot.Width,
                PipelineSnapshot.Height,
                PipelineSnapshot.FramesPerSecond,
                PipelineSnapshot.PresentMilliseconds,
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
            $"Live | {snapshot.Width}x{snapshot.Height} | {snapshot.FramesPerSecond:0.0} fps | present {snapshot.PresentMilliseconds:0.0} ms | render {snapshot.RenderLatencyMilliseconds:0.0} ms | dropped {snapshot.DroppedFrames} | {frame.TargetName}");
    }

    private enum OutputState
    {
        Idle,
        Error,
        Live,
        Paused,
    }

    private enum FallbackIcon
    {
        NoTarget,
        Paused,
        Error,
    }
}

public sealed record OutputPipelineSnapshot(
    long Sequence,
    int Width,
    int Height,
    double FramesPerSecond,
    double PresentMilliseconds,
    double RenderLatencyMilliseconds,
    long DroppedFrames,
    string TargetName)
{
    public static OutputPipelineSnapshot Empty { get; } = new(0, 0, 0, 0, 0, 0, 0, "No target");
}
