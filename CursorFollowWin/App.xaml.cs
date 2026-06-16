using Microsoft.Extensions.Logging;
using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;

namespace CursorFollowWin;

public partial class App : Application
{
    private const string SingleInstanceMutexName = "Local\\CursorFollowWin";
    private const int SwRestore = 9;

    private Mutex? _singleInstanceMutex;
    private MainWindow? _outputWindow;
    private TargetFollowService? _targetFollowService;
    private TrayIconService? _trayIcon;
    private HotkeyService? _hotkeyService;
    private PanelWindow? _panelWindow;
    private SettingsWindow? _settingsWindow;

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            AppLog.App.LogError(e.Exception, "Unhandled exception: {Message}", e.Message);
        };
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        AppLog.Initialize();

        _singleInstanceMutex = new Mutex(true, SingleInstanceMutexName, out var isFirstInstance);
        if (!isFirstInstance)
        {
            AppLog.App.LogInformation("Another instance is already running; activating it and exiting.");
            ActivateExistingInstance();
            Current.Exit();
            return;
        }

        AppLog.App.LogInformation("CursorFollowWin starting.");
        SettingsStore.Load();
        StartupRegistration.Apply(SettingsStore.Current.StartWithWindows);

        _outputWindow = new MainWindow(SettingsStore.Current);
        _outputWindow.ApplySettings(SettingsStore.Current);
        _targetFollowService = new TargetFollowService(_outputWindow);
        _outputWindow.ShowOutput();

        if (SettingsStore.Current.AutoShareOnLaunch)
        {
            _targetFollowService.Start();
        }

        AppLog.App.LogInformation("Creating tray icon.");
        _trayIcon = new TrayIconService(
            ShowPanel,
            ShowOutputWindow,
            HideOutputWindow,
            ShowSettings,
            ExitApplication);

        AppLog.App.LogInformation("Registering hotkeys.");
        _hotkeyService = new HotkeyService(ToggleAutoFollow, ToggleOutput);
        ApplyHotkeys(SettingsStore.Current);
        AppLog.App.LogInformation("Startup complete.");
    }

    private void ToggleAutoFollow()
    {
        if (_targetFollowService is null)
        {
            return;
        }

        _targetFollowService.SetEnabled(!_targetFollowService.IsEnabled);
    }

    private void ToggleOutput()
    {
        if (_outputWindow is null)
        {
            return;
        }

        if (_outputWindow.IsOutputVisible)
        {
            _outputWindow.HideOutput();
        }
        else
        {
            _outputWindow.ShowOutput();
        }
    }

    private string? ApplyHotkeys(AppSettings settings)
    {
        AppLog.Hotkeys.LogInformation(
            "Applying hotkeys from settings: auto-follow='{AutoFollow}', output='{Output}'.",
            settings.AutoFollowHotkey,
            settings.ToggleOutputHotkey);

        var conflict = _hotkeyService?.ApplyBindings(
            Hotkey.Parse(settings.AutoFollowHotkey),
            Hotkey.Parse(settings.ToggleOutputHotkey));

        if (conflict is not null)
        {
            AppLog.Hotkeys.LogWarning("Hotkey binding conflict: {Conflict}", conflict);
        }

        return conflict;
    }

    private void ShowPanel()
    {
        if (_outputWindow is null || _targetFollowService is null)
        {
            return;
        }

        _panelWindow ??= new PanelWindow(_outputWindow, _targetFollowService, ShowSettings, ExitApplication);
        _panelWindow.RefreshFromOutput();
        _panelWindow.ActivateNearTray();
    }

    private void ShowOutputWindow()
    {
        _outputWindow?.ShowOutput();
    }

    private void HideOutputWindow()
    {
        _outputWindow?.HideOutput();
    }

    private void ShowSettings()
    {
        if (_outputWindow is null)
        {
            return;
        }

        _settingsWindow ??= new SettingsWindow(SettingsStore.Current, SaveSettings);
        _settingsWindow.ResetDraft(SettingsStore.Current);
        _settingsWindow.ApplySettings(SettingsStore.Current);
        _settingsWindow.ShowNear(_panelWindow?.CurrentBounds());
    }

    private string? SaveSettings(AppSettings settings)
    {
        SettingsStore.Save(settings);
        StartupRegistration.Apply(settings.StartWithWindows);
        _outputWindow?.ApplySettings(settings);
        _settingsWindow?.ApplySettings(settings);
        _panelWindow?.RefreshFromOutput();
        return ApplyHotkeys(settings);
    }

    private void ExitApplication()
    {
        AppLog.App.LogInformation("CursorFollowWin exiting.");
        _hotkeyService?.Dispose();
        _trayIcon?.Dispose();
        _outputWindow?.DisposeCapture();
        _singleInstanceMutex?.Dispose();
        AppLog.Shutdown();
        Current.Exit();
    }

    private static void ActivateExistingInstance()
    {
        var outputWindow = FindWindow(null, WindowsGraphicsCaptureController.OutputWindowTitle);
        if (outputWindow == IntPtr.Zero)
        {
            return;
        }

        ShowWindow(outputWindow, SwRestore);
        SetForegroundWindow(outputWindow);
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string? lpClassName, string? lpWindowName);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
}
