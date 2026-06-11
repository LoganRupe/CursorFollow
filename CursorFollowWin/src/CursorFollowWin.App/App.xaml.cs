using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;

namespace CursorFollowWin_App;

public partial class App : Application
{
    private const string SingleInstanceMutexName = "Local\\CursorFollowWin.App";
    private const int SwRestore = 9;

    private Mutex? _singleInstanceMutex;
    private MainWindow? _outputWindow;
    private TargetFollowService? _targetFollowService;
    private TrayIconService? _trayIcon;
    private PanelWindow? _panelWindow;
    private SettingsWindow? _settingsWindow;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        _singleInstanceMutex = new Mutex(true, SingleInstanceMutexName, out var isFirstInstance);
        if (!isFirstInstance)
        {
            ActivateExistingInstance();
            Current.Exit();
            return;
        }

        SettingsStore.Load();

        _outputWindow = new MainWindow(SettingsStore.Current);
        _outputWindow.ApplySettings(SettingsStore.Current);
        _targetFollowService = new TargetFollowService(_outputWindow);
        _outputWindow.ShowOutput();

        if (SettingsStore.Current.AutoShareOnLaunch)
        {
            _targetFollowService.Start();
        }

        _trayIcon = new TrayIconService(
            ShowPanel,
            ShowOutputWindow,
            HideOutputWindow,
            ShowSettings,
            ExitApplication);
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

    private void SaveSettings(AppSettings settings)
    {
        SettingsStore.Save(settings);
        _outputWindow?.ApplySettings(settings);
        _settingsWindow?.ApplySettings(settings);
        _panelWindow?.RefreshFromOutput();
    }

    private void ExitApplication()
    {
        _trayIcon?.Dispose();
        _outputWindow?.DisposeCapture();
        _singleInstanceMutex?.Dispose();
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
