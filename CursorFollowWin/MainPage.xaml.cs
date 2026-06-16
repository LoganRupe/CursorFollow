using Microsoft.Extensions.Logging;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using System.Globalization;
using Windows.Graphics.Imaging;

namespace CursorFollowWin;

public sealed partial class MainPage : Page
{
    private readonly WindowsGraphicsCaptureController _captureController = new();
    private IntPtr _windowHandle;
    private OutputState _currentState = OutputState.Idle;
    private string _status = "Waiting for target selection";
    private string _targetName = "Manual target picker";
    private DateTimeOffset _lastPresentedAt;
    private double _smoothedFramesPerSecond;
    private double _smoothedRenderLatencyMs;

    public MainPage()
    {
        InitializeComponent();

        _captureController.FrameReady += CaptureController_FrameReady;
        _captureController.CaptureStopped += CaptureController_CaptureStopped;
        _captureController.CaptureFailed += CaptureController_CaptureFailed;

        UpdateState(OutputState.Idle);
    }

    public event EventHandler? OutputStateChanged;

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

        SelectTargetButton.IsEnabled = false;
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
        finally
        {
            SelectTargetButton.IsEnabled = true;
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
        UpdateState(OutputState.Idle);
    }

    public void ShowFallbackState() => UpdateState(
        OutputState.Error,
        "Fallback state for target-missing, protected-content, or renderer errors.");

    public void SetOverlayVisible(bool isVisible)
    {
        TelemetryOverlay.Visibility = isVisible ? Visibility.Visible : Visibility.Collapsed;
    }

    public void ApplyCaptureQuality(string quality)
    {
        _captureController.ApplyQuality(quality);
    }

    public void ApplyOutputScaleMode(string scaleMode)
    {
        // The output Border has a corner radius, which clips the Viewbox child, so
        // Fill/Actual content that overflows the window is cropped to the frame.
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

    private async void SelectTargetButton_Click(object sender, RoutedEventArgs e)
    {
        await SelectTargetAsync();
    }

    private void StopButton_Click(object sender, RoutedEventArgs e) => StopCapture();

    private void FallbackButton_Click(object sender, RoutedEventArgs e) => ShowFallbackState();

    private void CaptureController_FrameReady(CapturedFrame frame)
    {
        var queued = DispatcherQueue.TryEnqueue(async () =>
        {
            using var bitmap = frame.Bitmap;
            var source = new SoftwareBitmapSource();
            await source.SetBitmapAsync(bitmap);

            CaptureImage.Source = source;
            FrameSurface.Width = Math.Max(1, frame.ContentSize.Width);
            FrameSurface.Height = Math.Max(1, frame.ContentSize.Height);
            FrameText.Text = $"Frame {frame.Sequence:000000}";
            TimestampText.Text = frame.Timestamp.ToString("HH:mm:ss.fff");
            StateText.Text = $"Capturing {frame.TargetName}";
            _targetName = frame.TargetName;
            _currentState = OutputState.Live;
            UpdatePipelineSnapshot(frame);
            SetStatus(FormatLiveStatus(frame));
            FallbackOverlay.Visibility = Visibility.Collapsed;
            OutputControlsBar.Visibility = Visibility.Collapsed;
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

        if (state == OutputState.Live)
        {
            FallbackOverlay.Visibility = Visibility.Collapsed;
            OutputControlsBar.Visibility = Visibility.Collapsed;
            StateText.Text = "Live capture";
            SetStatus("Waiting for first captured frame");
            return;
        }

        FallbackOverlay.Visibility = Visibility.Visible;
        OutputControlsBar.Visibility = Visibility.Visible;

        if (state == OutputState.Idle)
        {
            StateText.Text = "No target selected";
            _targetName = "Manual target picker";
            SetStatus(detail ?? "Waiting for target selection");
            FallbackTitle.Text = "Select a target";
            FallbackDetail.Text = detail ?? "Choose a window from the Windows capture picker to render it here.";
            return;
        }

        AppLog.Output.LogWarning("Output entered fallback/error state: {Detail}", detail ?? "unspecified");
        StateText.Text = "Error / fallback";
        SetStatus(detail ?? "Error / fallback output");
        FallbackTitle.Text = "Fallback frame";
        FallbackDetail.Text = detail ?? "The capture pipeline reported a target-missing, protected-content, or renderer error.";
    }

    private void SetStatus(string status)
    {
        _status = status;
        StatusText.Text = status;
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
