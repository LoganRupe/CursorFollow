using Microsoft.UI.Xaml;

namespace CursorFollowWin;

public sealed class TargetFollowService
{
    private static readonly TimeSpan AutoFollowDebounce = TimeSpan.FromMilliseconds(350);

    private readonly MainWindow _outputWindow;
    private readonly WindowTracker _windowTracker = new();
    private readonly DispatcherTimer _timer = new();
    private TrackedWindow? _pendingTarget;
    private DateTimeOffset _pendingSince;
    private int _captureInFlight;

    public TargetFollowService(MainWindow outputWindow)
    {
        _outputWindow = outputWindow;
        _timer.Interval = TimeSpan.FromMilliseconds(250);
        _timer.Tick += Timer_Tick;

        _outputWindow.OutputStateChanged += (_, _) => SyncCapturedState();
        if (_outputWindow.OutputPage is not null)
        {
            _outputWindow.OutputPage.OutputStateChanged += (_, _) => SyncCapturedState();
        }
    }

    public event EventHandler? StateChanged;

    public bool IsEnabled { get; private set; }

    public IntPtr CapturedWindowHandle { get; private set; }

    public string Status { get; private set; } = "Auto follow ready";

    public void Start() => SetEnabled(true);

    public void SetEnabled(bool isEnabled)
    {
        if (IsEnabled == isEnabled)
        {
            RaiseStateChanged();
            return;
        }

        IsEnabled = isEnabled;
        _pendingTarget = null;
        _pendingSince = DateTimeOffset.MinValue;

        if (IsEnabled)
        {
            Status = "Auto follow active";
            _timer.Start();
        }
        else
        {
            Status = "Manual target mode";
            _timer.Stop();
        }

        RaiseStateChanged();
    }

    public bool IsAllowed(TrackedWindow window) => _windowTracker.IsAllowed(window, SettingsStore.Current);

    public async Task<bool> CaptureWindowAsync(TrackedWindow window, bool showOutput, string source)
    {
        if (Interlocked.Exchange(ref _captureInFlight, 1) == 1)
        {
            return false;
        }

        try
        {
            return await CaptureWindowCoreAsync(window, showOutput, source);
        }
        finally
        {
            Interlocked.Exchange(ref _captureInFlight, 0);
        }
    }

    private async Task<bool> CaptureWindowCoreAsync(TrackedWindow window, bool showOutput, string source)
    {
        if (!IsAllowed(window))
        {
            Status = $"Blocked by {SettingsStore.Current.WindowFilterMode}: {window.AppName}";
            RaiseStateChanged();
            return false;
        }

        if (showOutput)
        {
            _outputWindow.ShowOutput(activate: false);
        }

        if (_outputWindow.OutputPage is not null && await _outputWindow.OutputPage.CaptureWindowAsync(window))
        {
            CapturedWindowHandle = window.Handle;
            Status = $"{source}: {window.AppName}";
            RaiseStateChanged();
            return true;
        }

        CapturedWindowHandle = IntPtr.Zero;
        Status = _outputWindow.OutputPage?.Status ?? "Target unavailable; output held steady";
        RaiseStateChanged();
        return false;
    }

    private async void Timer_Tick(object? sender, object e)
    {
        var candidate = _windowTracker.GetCursorWindowCandidate() ?? _windowTracker.GetForegroundWindowCandidate();
        if (candidate is null || !IsAllowed(candidate) || candidate.Handle == CapturedWindowHandle)
        {
            _pendingTarget = null;
            return;
        }

        var now = DateTimeOffset.Now;
        if (_pendingTarget?.Handle != candidate.Handle)
        {
            _pendingTarget = candidate;
            _pendingSince = now;
            Status = $"Following {candidate.AppName}...";
            RaiseStateChanged();
            return;
        }

        if (now - _pendingSince < AutoFollowDebounce)
        {
            return;
        }

        await CaptureWindowAsync(candidate, showOutput: true, source: "Auto");
        _pendingTarget = null;
    }

    private void SyncCapturedState()
    {
        if (_outputWindow.OutputPage?.IsCapturing != true)
        {
            CapturedWindowHandle = IntPtr.Zero;
        }

        RaiseStateChanged();
    }

    private void RaiseStateChanged() => StateChanged?.Invoke(this, EventArgs.Empty);
}