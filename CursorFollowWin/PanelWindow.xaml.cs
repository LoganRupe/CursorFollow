using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using System.Runtime.InteropServices;
using Windows.Graphics;
using WinRT.Interop;

namespace CursorFollowWin;

public sealed partial class PanelWindow : Window
{
    private static readonly TimeSpan DismissCheckInterval = TimeSpan.FromMilliseconds(150);
    private static readonly SolidColorBrush ActiveSegmentBrush = new(Windows.UI.Color.FromArgb(255, 30, 155, 255));
    private static readonly SolidColorBrush InactiveSegmentBrush = new(Windows.UI.Color.FromArgb(0, 0, 0, 0));
    private static readonly SolidColorBrush PrimaryTextBrush = new(Windows.UI.Color.FromArgb(255, 232, 237, 245));
    private static readonly SolidColorBrush MutedTextBrush = new(Windows.UI.Color.FromArgb(255, 174, 184, 200));
    // Resume = green play (matches macOS .tint(.green)); Pause = red bars (matches .tint(.red)).
    private static readonly SolidColorBrush ResumeBackgroundBrush = new(Windows.UI.Color.FromArgb(255, 20, 62, 43));
    private static readonly SolidColorBrush ResumeForegroundBrush = new(Windows.UI.Color.FromArgb(255, 57, 233, 130));
    private static readonly SolidColorBrush PauseBackgroundBrush = new(Windows.UI.Color.FromArgb(255, 62, 20, 20));
    private static readonly SolidColorBrush PauseForegroundBrush = new(Windows.UI.Color.FromArgb(255, 255, 112, 112));
    private static readonly SolidColorBrush LiveDotBrush = new(Windows.UI.Color.FromArgb(255, 57, 233, 130));
    private static readonly SolidColorBrush IdleDotBrush = new(Windows.UI.Color.FromArgb(255, 154, 166, 183));
    private const string PlayGlyph = "";
    private const string PauseGlyph = "";
    private const int GwlStyle = -16;
    private const int GwlExStyle = -20;
    private const int SwHide = 0;
    private const int SwShow = 5;
    private const int SwpNoSize = 0x0001;
    private const int SwpNoMove = 0x0002;
    private const int SwpNoZOrder = 0x0004;
    private const int SwpNoActivate = 0x0010;
    private const int SwpShowWindow = 0x0040;
    private const int SwpFrameChanged = 0x0020;
    private const long WsBorder = 0x00800000L;
    private const long WsCaption = 0x00C00000L;
    private const long WsDlgFrame = 0x00400000L;
    private const long WsThickFrame = 0x00040000L;
    private const long WsExToolWindow = 0x00000080L;
    private const long WsExAppWindow = 0x00040000L;
    private const int DwmwaBorderColor = 34;
    private const uint DwmwaPanelBorderColor = 0x00201811;
    private static readonly IntPtr HwndTopMost = new(-1);
    private static readonly IntPtr HwndNoTopMost = new(-2);

    private readonly MainWindow _outputWindow;
    private readonly TargetFollowService _targetFollowService;
    private readonly Action _showSettings;
    private readonly Action _quit;
    private readonly IWindowTracker _windowTracker = new WindowTracker();
    private readonly DispatcherTimer _dismissTimer = new();
    private readonly IntPtr _windowHandle;
    private IReadOnlyList<WindowListItem> _windows = Array.Empty<WindowListItem>();
    private bool _isLoadingSettings;
    private bool _isShowingQuitDialog;

    public PanelWindow(MainWindow outputWindow, TargetFollowService targetFollowService, Action showSettings, Action quit)
    {
        _outputWindow = outputWindow;
        _targetFollowService = targetFollowService;
        _showSettings = showSettings;
        _quit = quit;

        InitializeComponent();
        _windowHandle = WindowNative.GetWindowHandle(this);
        AppWindow.SetIcon("Assets/AppIcon.ico");
        AppWindow.Resize(new SizeInt32(274, 494));
        ConfigureTrayPanelChrome();

        _dismissTimer.Interval = DismissCheckInterval;
        _dismissTimer.Tick += DismissTimer_Tick;

        _outputWindow.OutputStateChanged += (_, _) => RefreshFromOutput();
        _targetFollowService.StateChanged += (_, _) => RefreshFromOutput();
        if (_outputWindow.OutputPage is not null)
        {
            _outputWindow.OutputPage.OutputStateChanged += (_, _) => RefreshFromOutput();
        }
        Activated += PanelWindow_Activated;

        LoadFilterSettings();
        RefreshWindowInventory();
        RefreshFromOutput();
        RefreshTargetModeButtons();
    }

    public void ActivateNearTray()
    {
        PositionNearTray();
        ShowPanel();
        Activate();
    }

    public RectInt32 CurrentBounds()
    {
        var position = AppWindow.Position;
        var size = AppWindow.Size;
        return new RectInt32(position.X, position.Y, size.Width, size.Height);
    }

    public void RefreshFromOutput()
    {
        var page = _outputWindow.OutputPage;
        var isCapturing = page?.IsCapturing == true;

        LiveBadgeText.Text = isCapturing ? "Live" : "Idle";
        TargetText.Text = page?.TargetName ?? "Manual target picker";
        StatusText.Text = page?.Status ?? "Waiting for target selection";
        OutputButton.Content = _outputWindow.IsOutputVisible ? "Hide" : "Show";
        LiveDot.Fill = isCapturing ? LiveDotBrush : IdleDotBrush;

        // Mirror the macOS status bar: a red Pause while capturing (stops the recording without
        // closing the output window) and a green Resume otherwise (re-starts capture of the target).
        StartButtonText.Text = isCapturing ? "Pause" : "Resume";
        StartButtonIcon.Glyph = isCapturing ? PauseGlyph : PlayGlyph;
        StartButton.Background = isCapturing ? PauseBackgroundBrush : ResumeBackgroundBrush;
        StartButton.Foreground = isCapturing ? PauseForegroundBrush : ResumeForegroundBrush;
        ToolTipService.SetToolTip(
            StartButton,
            isCapturing ? "Pause output without closing the shared window" : "Resume output");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(StartButton, isCapturing ? "Pause" : "Resume");
        StartButton.IsEnabled = page is not null;
        StopButton.IsEnabled = page is not null;
        UpdateFilterStatus();
    }

    private async void StartButton_Click(object sender, RoutedEventArgs e)
    {
        // While capturing the button acts as Pause: stop the screen recording but keep the output
        // window and remembered target so the next click can resume it (parity with macOS userStop()).
        if (_outputWindow.OutputPage?.IsCapturing == true)
        {
            _targetFollowService.MarkUserStopped();
            _outputWindow.OutputPage.StopCapture();
            RefreshFromOutput();
            return;
        }

        // Resume: clear the user-pause gate so auto-follow can re-engage, then re-start capture.
        _targetFollowService.ClearUserStopped();
        _outputWindow.ShowOutput();
        if (_outputWindow.OutputPage is not null)
        {
            if (SelectedWindow() is { } window)
            {
                if (!IsAllowed(window))
                {
                    FilterStatusText.Text = $"Blocked by {SettingsStore.Current.WindowFilterMode}";
                    return;
                }

                await CaptureWindowAsync(window, showOutput: false, source: "Manual");
            }
            else
            {
                await _outputWindow.OutputPage.SelectTargetAsync();
            }
        }
        RefreshFromOutput();
    }

    private void StopButton_Click(object sender, RoutedEventArgs e)
    {
        _outputWindow.OutputPage?.StopCapture();
        RefreshFromOutput();
    }

    private void OutputButton_Click(object sender, RoutedEventArgs e)
    {
        if (_outputWindow.IsOutputVisible)
        {
            _outputWindow.HideOutput();
        }
        else
        {
            _outputWindow.ShowOutput();
        }

        RefreshFromOutput();
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        RefreshWindowInventory();
        RefreshFromOutput();
    }

    private void SetAutoFollowEnabled(bool isEnabled)
    {
        _targetFollowService.SetEnabled(isEnabled);
        UpdateFilterStatus();
    }

    private void WindowListView_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is WindowListItem item)
        {
            WindowListView.SelectedItem = item;
            TargetText.Text = item.Window.DisplayName;
            ToggleSelectedWindowForActiveFilter(item.Window);
        }
    }

    private void WindowListView_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SelectedWindow() is { } window)
        {
            TargetText.Text = window.DisplayName;
        }

        RefreshFilterButtons();
    }

    private void IncludeButton_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedWindow() is { } window)
        {
            var settings = SettingsStore.Current;
            SaveFilterSettings(settings with
            {
                IncludeWindowIdentities = AddIdentity(settings.IncludeWindowIdentities, window.Identity),
                ExcludeWindowIdentities = RemoveIdentity(settings.ExcludeWindowIdentities, window.Identity),
            });
        }
    }

    private void ExcludeButton_Click(object sender, RoutedEventArgs e)
    {
        if (SelectedWindow() is { } window)
        {
            var settings = SettingsStore.Current;
            SaveFilterSettings(settings with
            {
                ExcludeWindowIdentities = AddIdentity(settings.ExcludeWindowIdentities, window.Identity),
                IncludeWindowIdentities = RemoveIdentity(settings.IncludeWindowIdentities, window.Identity),
            });
        }
    }

    private void SettingsButton_Click(object sender, RoutedEventArgs e) => _showSettings();

    private async void QuitButton_Click(object sender, RoutedEventArgs e)
    {
        if (await ConfirmQuitAsync())
        {
            _quit();
        }
    }

    /// <summary>
    /// Shows a dark-themed "Quit CursorFollow?" confirmation matching the macOS app, with a red
    /// destructive Quit button. Returns true only if the user confirms.
    /// </summary>
    private async Task<bool> ConfirmQuitAsync()
    {
        if (_isShowingQuitDialog || Content?.XamlRoot is null)
        {
            return false;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            RequestedTheme = ElementTheme.Dark,
            Title = "Quit CursorFollow?",
            Content = new TextBlock
            {
                Text = "Are you sure you want to quit CursorFollow?",
                TextWrapping = TextWrapping.Wrap,
                FontSize = 13,
                Foreground = DialogBrush(0xAE, 0xB8, 0xC8),
            },
            PrimaryButtonText = "Quit",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };

        // Fit the compact tray panel (274px wide) and match its dark palette. Overriding the
        // button theme brushes (incl. pointer-over / pressed) keeps the colors stable across
        // hover states; the Quit button is the default, so it picks up the Accent* brushes.
        var res = dialog.Resources;
        res["ContentDialogBackground"] = DialogBrush(0x1C, 0x27, 0x33);
        res["ContentDialogBorderBrush"] = DialogBrush(0x2A, 0x3A, 0x4A);
        res["ContentDialogForeground"] = DialogBrush(0xEE, 0xF3, 0xFA);
        res["ContentDialogMinWidth"] = 250.0;
        res["ContentDialogMaxWidth"] = 258.0;
        res["ButtonBackground"] = DialogBrush(0x2B, 0x36, 0x46);
        res["ButtonBackgroundPointerOver"] = DialogBrush(0x35, 0x41, 0x52);
        res["ButtonBackgroundPressed"] = DialogBrush(0x23, 0x2D, 0x3A);
        res["ButtonForeground"] = DialogBrush(0xE8, 0xED, 0xF5);
        res["ButtonForegroundPointerOver"] = DialogBrush(0xE8, 0xED, 0xF5);
        res["ButtonForegroundPressed"] = DialogBrush(0xE8, 0xED, 0xF5);
        res["AccentButtonBackground"] = DialogBrush(0xD9, 0x34, 0x2B);
        res["AccentButtonBackgroundPointerOver"] = DialogBrush(0xE2, 0x44, 0x3B);
        res["AccentButtonBackgroundPressed"] = DialogBrush(0xBC, 0x2A, 0x23);
        res["AccentButtonForeground"] = DialogBrush(0xFF, 0xFF, 0xFF);
        res["AccentButtonForegroundPointerOver"] = DialogBrush(0xFF, 0xFF, 0xFF);
        res["AccentButtonForegroundPressed"] = DialogBrush(0xFF, 0xFF, 0xFF);

        _isShowingQuitDialog = true;
        try
        {
            return await dialog.ShowAsync() == ContentDialogResult.Primary;
        }
        finally
        {
            _isShowingQuitDialog = false;
        }
    }

    private static SolidColorBrush DialogBrush(byte r, byte g, byte b) =>
        new(Windows.UI.Color.FromArgb(255, r, g, b));

    private void AutoFollowModeButton_Click(object sender, RoutedEventArgs e)
    {
        SetAutoFollowFromSegment(true);
    }

    private void ManualModeButton_Click(object sender, RoutedEventArgs e)
    {
        SetAutoFollowFromSegment(false);
    }

    private void AllFilterButton_Click(object sender, RoutedEventArgs e) => SaveSelectedFilterMode(WindowFilterMode.All);

    private void ExcludeFilterButton_Click(object sender, RoutedEventArgs e) => SaveSelectedFilterMode(WindowFilterMode.Exclude);

    private void IncludeFilterButton_Click(object sender, RoutedEventArgs e) => SaveSelectedFilterMode(WindowFilterMode.Include);

    private async Task CaptureWindowAsync(TrackedWindow window, bool showOutput, string source)
    {
        if (await _targetFollowService.CaptureWindowAsync(window, showOutput, source))
        {
            TargetText.Text = window.DisplayName;
            RefreshWindowInventory(window.Handle);
        }

        RefreshFromOutput();
    }

    private void PanelWindow_Activated(object sender, WindowActivatedEventArgs args)
    {
        // While the quit confirmation is up, the modal dialog can take focus within the window;
        // don't let a transient deactivation hide the panel out from under the dialog.
        if (_isShowingQuitDialog)
        {
            return;
        }

        if (args.WindowActivationState == WindowActivationState.Deactivated)
        {
            HidePanel();
        }
    }

    private void DismissTimer_Tick(object? sender, object e)
    {
        if (_isShowingQuitDialog)
        {
            return;
        }

        var foregroundWindow = GetForegroundWindow();
        if (foregroundWindow != IntPtr.Zero && foregroundWindow != _windowHandle)
        {
            HidePanel();
        }
    }

    private void RefreshWindowInventory(IntPtr selectedHandle = default)
    {
        var previousHandle = selectedHandle != IntPtr.Zero
            ? selectedHandle
            : SelectedWindow()?.Handle ?? IntPtr.Zero;

        var settings = SettingsStore.Current;
        _windows = _windowTracker
            .RefreshWindows()
            .Select(window => new WindowListItem(
                window,
                settings.IncludeWindowIdentities.Contains(window.Identity, StringComparer.OrdinalIgnoreCase),
                settings.ExcludeWindowIdentities.Contains(window.Identity, StringComparer.OrdinalIgnoreCase),
                window.Handle == _targetFollowService.CapturedWindowHandle))
            .ToArray();
        WindowListView.ItemsSource = _windows;
        WindowCountText.Text = $"{_windows.Count} found";

        if (previousHandle != IntPtr.Zero)
        {
            WindowListView.SelectedItem = _windows.FirstOrDefault(item => item.Window.Handle == previousHandle);
        }

        if (WindowListView.SelectedItem is null && _windows.Count > 0)
        {
            WindowListView.SelectedIndex = 0;
        }

        RefreshFilterButtons();
        UpdateFilterStatus();
    }

    private void LoadFilterSettings()
    {
        _isLoadingSettings = true;
        RefreshFilterModeButtons();
        _isLoadingSettings = false;
    }

    private void SaveFilterSettings(AppSettings settings)
    {
        SettingsStore.Save(settings);
        LoadFilterSettings();
        RefreshWindowInventory();
    }

    private bool IsAllowed(TrackedWindow window) => _targetFollowService.IsAllowed(window);

    private void RefreshFilterButtons()
    {
        var hasSelection = SelectedWindow() is not null;
        IncludeButton.IsEnabled = hasSelection;
        ExcludeButton.IsEnabled = hasSelection;
    }

    private void UpdateFilterStatus()
    {
        var settings = SettingsStore.Current;
        FilterStatusText.Text = $"{settings.WindowFilterMode}: {settings.IncludeWindowIdentities.Length} in, {settings.ExcludeWindowIdentities.Length} out | {_targetFollowService.Status}";
        RefreshTargetModeButtons();
        RefreshFilterModeButtons();
    }

    private void SaveSelectedFilterMode(WindowFilterMode mode)
    {
        if (_isLoadingSettings || SettingsStore.Current.WindowFilterMode == mode)
        {
            RefreshFilterModeButtons();
            return;
        }

        SaveFilterSettings(SettingsStore.Current with
        {
            WindowFilterMode = mode,
        });
    }

    private void ToggleSelectedWindowForActiveFilter(TrackedWindow window)
    {
        var settings = SettingsStore.Current;
        if (settings.WindowFilterMode == WindowFilterMode.Include)
        {
            if (ContainsIdentity(settings.IncludeWindowIdentities, window.Identity))
            {
                SaveFilterSettings(settings with
                {
                    IncludeWindowIdentities = RemoveIdentity(settings.IncludeWindowIdentities, window.Identity),
                });
                return;
            }

            SaveFilterSettings(settings with
            {
                IncludeWindowIdentities = AddIdentity(settings.IncludeWindowIdentities, window.Identity),
                ExcludeWindowIdentities = RemoveIdentity(settings.ExcludeWindowIdentities, window.Identity),
            });
        }
        else if (settings.WindowFilterMode == WindowFilterMode.Exclude)
        {
            if (ContainsIdentity(settings.ExcludeWindowIdentities, window.Identity))
            {
                SaveFilterSettings(settings with
                {
                    ExcludeWindowIdentities = RemoveIdentity(settings.ExcludeWindowIdentities, window.Identity),
                });
                return;
            }

            SaveFilterSettings(settings with
            {
                ExcludeWindowIdentities = AddIdentity(settings.ExcludeWindowIdentities, window.Identity),
                IncludeWindowIdentities = RemoveIdentity(settings.IncludeWindowIdentities, window.Identity),
            });
        }
    }

    private TrackedWindow? SelectedWindow() => WindowListView.SelectedItem switch
    {
        WindowListItem item => item.Window,
        TrackedWindow window => window,
        _ => null,
    };

    private void SetAutoFollowFromSegment(bool isOn)
    {
        if (_targetFollowService.IsEnabled == isOn)
        {
            RefreshTargetModeButtons();
            return;
        }

        SetAutoFollowEnabled(isOn);
    }

    private void RefreshTargetModeButtons()
    {
        SetSegmentButtonState(AutoFollowModeButton, _targetFollowService.IsEnabled);
        SetSegmentButtonState(ManualModeButton, !_targetFollowService.IsEnabled);
    }

    private void RefreshFilterModeButtons()
    {
        var mode = SettingsStore.Current.WindowFilterMode;
        SetSegmentButtonState(AllFilterButton, mode == WindowFilterMode.All);
        SetSegmentButtonState(ExcludeFilterButton, mode == WindowFilterMode.Exclude);
        SetSegmentButtonState(IncludeFilterButton, mode == WindowFilterMode.Include);
    }

    private static void SetSegmentButtonState(Button button, bool isActive)
    {
        button.Background = isActive ? ActiveSegmentBrush : InactiveSegmentBrush;
        button.Foreground = isActive ? PrimaryTextBrush : MutedTextBrush;
    }

    private static bool ContainsIdentity(IEnumerable<string> identities, string identity) => identities
        .Contains(identity, StringComparer.OrdinalIgnoreCase);

    private static string[] AddIdentity(IEnumerable<string> identities, string identity) => identities
        .Append(identity)
        .Where(value => !string.IsNullOrWhiteSpace(value))
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
        .ToArray();

    private static string[] RemoveIdentity(IEnumerable<string> identities, string identity) => identities
        .Where(value => !string.Equals(value, identity, StringComparison.OrdinalIgnoreCase))
        .ToArray();

    private void ConfigureTrayPanelChrome()
    {
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.SetBorderAndTitleBar(false, false);
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
        }

        HideFromTaskbar(_windowHandle);
        RemoveNativeWindowBorder(_windowHandle);

        var borderColor = DwmwaPanelBorderColor;
        DwmSetWindowAttribute(_windowHandle, DwmwaBorderColor, ref borderColor, sizeof(uint));
    }

    private static void HideFromTaskbar(IntPtr windowHandle)
    {
        var exStyle = GetWindowLongPtr(windowHandle, GwlExStyle).ToInt64();
        exStyle = (exStyle | WsExToolWindow) & ~WsExAppWindow;
        SetWindowLongPtr(windowHandle, GwlExStyle, new IntPtr(exStyle));
        SetWindowPos(windowHandle, IntPtr.Zero, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoZOrder | SwpNoActivate | SwpFrameChanged);
    }

    private void HidePanel()
    {
        _dismissTimer.Stop();
        ShowWindow(_windowHandle, SwHide);
    }

    private void ShowPanel()
    {
        ShowWindow(_windowHandle, SwShow);
        SetWindowPos(_windowHandle, HwndTopMost, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpShowWindow);
        SetWindowPos(_windowHandle, HwndNoTopMost, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpShowWindow);
        SetForegroundWindow(_windowHandle);
        _dismissTimer.Start();
    }

    private static void RemoveNativeWindowBorder(IntPtr windowHandle)
    {
        var style = GetWindowLongPtr(windowHandle, GwlStyle).ToInt64();
        style &= ~(WsCaption | WsBorder | WsDlgFrame | WsThickFrame);
        SetWindowLongPtr(windowHandle, GwlStyle, new IntPtr(style));
        SetWindowPos(windowHandle, IntPtr.Zero, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoZOrder | SwpFrameChanged);
    }

    private void PositionNearTray()
    {
        var windowId = Win32Interop.GetWindowIdFromWindow(_windowHandle);
        var displayArea = DisplayArea.GetFromWindowId(windowId, DisplayAreaFallback.Nearest);
        var workArea = displayArea.WorkArea;
        var width = AppWindow.Size.Width;
        var height = AppWindow.Size.Height;
        AppWindow.Move(new PointInt32(workArea.X + workArea.Width - width - 12, workArea.Y + workArea.Height - height - 12));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int dwAttribute, ref uint pvAttribute, int cbAttribute);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, int uFlags);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

}

public sealed class WindowListItem
{
    public WindowListItem(
        TrackedWindow window,
        bool isIncluded,
        bool isExcluded,
        bool isCaptured)
    {
        Window = window;
        MarkerGlyph = isCaptured || isIncluded
            ? "\uE73E"
            : isExcluded
                ? "\uE711"
                : "\uE739";
        MarkerBrush = new SolidColorBrush(isCaptured || isIncluded
            ? Windows.UI.Color.FromArgb(255, 56, 224, 127)
            : isExcluded
                ? Windows.UI.Color.FromArgb(255, 255, 112, 112)
                : Windows.UI.Color.FromArgb(255, 135, 148, 166));
    }

    public TrackedWindow Window { get; }

    public string Title => Window.Title;

    public string AppName => Window.AppName;

    public string SizeLabel => Window.SizeLabel;

    public string MarkerGlyph { get; }

    public SolidColorBrush MarkerBrush { get; }
}

