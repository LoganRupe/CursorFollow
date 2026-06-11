using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using System.Runtime.InteropServices;
using Windows.Graphics;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using WinRT.Interop;

namespace CursorFollowWin_App;

public sealed partial class SettingsWindow : Window
{
    private const int GwlStyle = -16;
    private const int GwlExStyle = -20;
    private const int SwHide = 0;
    private const int SwShow = 5;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpFrameChanged = 0x0020;
    private const long WsBorder = 0x00800000L;
    private const long WsCaption = 0x00C00000L;
    private const long WsDlgFrame = 0x00400000L;
    private const long WsThickFrame = 0x00040000L;
    private const long WsExToolWindow = 0x00000080L;
    private const long WsExAppWindow = 0x00040000L;
    private const int DwmwaBorderColor = 34;
    private const uint DwmwaSettingsBorderColor = 0x00201811;
    private const int WindowWidth = 840;
    private const int WindowHeight = 646;
    private const int AnchorGap = 8;

    private readonly Func<AppSettings, string?> _save;
    private readonly IntPtr _windowHandle;
    private readonly ToggleSwitch _startWithWindowsSwitch = new() { Header = "Start with Windows", Foreground = WhiteBrush };
    private readonly ToggleSwitch _autoShareSwitch = new() { Header = "Auto-share on launch", Foreground = WhiteBrush };
    private readonly ToggleSwitch _hideWhenNotSharingSwitch = new() { Header = "Hide when not sharing", Foreground = WhiteBrush };
    private readonly ToggleSwitch _pinOutputSwitch = new() { Header = "Pin output on top", Foreground = WhiteBrush };
    private readonly ToggleSwitch _showTaskbarIconSwitch = new() { Header = "Show app icon in taskbar", Foreground = WhiteBrush };
    private readonly ToggleSwitch _showOverlaySwitch = new() { Header = "Show overlay", Foreground = WhiteBrush };
    private readonly Button _balancedQualityButton = new() { Content = "BALANCED" };
    private readonly Button _performanceQualityButton = new() { Content = "PERFORMANT" };
    private readonly Button _lowLatencyQualityButton = new() { Content = "LOW-LATENCY" };
    private readonly HotkeyCaptureControl _autoFollowHotkey = new();
    private readonly HotkeyCaptureControl _toggleOutputHotkey = new();
    private readonly Button _fitScaleButton = new();
    private readonly Button _fillScaleButton = new();
    private readonly Button _actualScaleButton = new();
    private readonly TextBlock _hideWhenNotSharingSubtitle = CreateSubtitleBlock("Hide the output window while paused");
    private readonly TextBlock _pinOutputSubtitle = CreateSubtitleBlock("Keep output window above other windows");
    private string _selectedQuality = "Balanced";
    private string _selectedScaleMode = "Fit";
    private bool _syncingExclusiveToggles;
    private TextBlock _statusText = null!;
    private Ellipse _statusDot = null!;

    private static readonly SolidColorBrush WhiteBrush = new(Windows.UI.Color.FromArgb(255, 255, 255, 255));
    private static readonly SolidColorBrush MutedBrush = new(Windows.UI.Color.FromArgb(255, 174, 184, 200));
    private static readonly SolidColorBrush BackgroundBrush = new(Windows.UI.Color.FromArgb(255, 9, 13, 29));
    private static readonly SolidColorBrush CardBrush = new(Windows.UI.Color.FromArgb(255, 25, 30, 46));
    private static readonly SolidColorBrush CardBorderBrush = new(Windows.UI.Color.FromArgb(255, 38, 45, 67));
    private static readonly SolidColorBrush DividerBrush = new(Windows.UI.Color.FromArgb(255, 63, 70, 92));
    private static readonly SolidColorBrush AccentBrush = new(Windows.UI.Color.FromArgb(255, 32, 111, 230));
    private static readonly SolidColorBrush SecondaryButtonBrush = new(Windows.UI.Color.FromArgb(255, 42, 46, 61));
    private static readonly SolidColorBrush PrimaryButtonBrush = new(Windows.UI.Color.FromArgb(255, 184, 200, 255));
    private static readonly SolidColorBrush PrimaryButtonTextBrush = new(Windows.UI.Color.FromArgb(255, 18, 31, 61));
    private static readonly SolidColorBrush SegmentBackgroundBrush = new(Windows.UI.Color.FromArgb(255, 43, 47, 62));
    private static readonly SolidColorBrush DangerBrush = new(Windows.UI.Color.FromArgb(255, 255, 123, 123));

    public SettingsWindow(AppSettings settings, Func<AppSettings, string?> save)
    {
        _save = save;
        _windowHandle = WindowNative.GetWindowHandle(this);

        Title = "CursorFollow Settings";
        AppWindow.SetIcon("Assets/AppIcon.ico");
        AppWindow.Resize(new SizeInt32(WindowWidth, WindowHeight));
        ConfigureBorderlessChrome();

        Content = CreateContent();
        ResetDraft(settings);
        ApplySettings(settings);
    }

    public void ResetDraft(AppSettings settings)
    {
        _startWithWindowsSwitch.IsOn = settings.StartWithWindows;
        _autoShareSwitch.IsOn = settings.AutoShareOnLaunch;

        // Set the mutually exclusive toggles under the sync guard so their Toggled handlers
        // don't fight each other, then reconcile enabled/explanation state once.
        _syncingExclusiveToggles = true;
        _hideWhenNotSharingSwitch.IsOn = settings.HideWhenNotSharing;
        _pinOutputSwitch.IsOn = settings.PinOutputOnTop && !settings.HideWhenNotSharing;
        _syncingExclusiveToggles = false;
        UpdateExclusiveToggleState();

        _showTaskbarIconSwitch.IsOn = settings.ShowTaskbarIcon;
        _showOverlaySwitch.IsOn = settings.ShowOverlay;
        _autoFollowHotkey.Value = Hotkey.Parse(settings.AutoFollowHotkey);
        _toggleOutputHotkey.Value = Hotkey.Parse(settings.ToggleOutputHotkey);
        SelectQuality(settings.CaptureQuality);
        SelectScaleMode(settings.OutputScaleMode);
    }

    public void ApplySettings(AppSettings settings)
    {
        SetTaskbarIconVisible(settings.ShowTaskbarIcon);
    }

    public void ShowNear(RectInt32? anchorBounds)
    {
        PositionNearAnchor(anchorBounds);
        ShowWindow(_windowHandle, SwShow);
        Activate();
    }

    private void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        var current = SettingsStore.Current;
        var conflict = _save(new AppSettings
        {
            StartWithWindows = _startWithWindowsSwitch.IsOn,
            AutoShareOnLaunch = _autoShareSwitch.IsOn,
            HideWhenNotSharing = _hideWhenNotSharingSwitch.IsOn,
            PinOutputOnTop = _pinOutputSwitch.IsOn,
            ShowTaskbarIcon = _showTaskbarIconSwitch.IsOn,
            ShowOverlay = _showOverlaySwitch.IsOn,
            CaptureQuality = SelectedQuality(),
            OutputScaleMode = _selectedScaleMode,
            WindowFilterMode = current.WindowFilterMode,
            IncludeWindowIdentities = current.IncludeWindowIdentities,
            ExcludeWindowIdentities = current.ExcludeWindowIdentities,
            AutoFollowHotkey = _autoFollowHotkey.Value.Format(),
            ToggleOutputHotkey = _toggleOutputHotkey.Value.Format(),
        });

        // Settings are saved either way; a conflict only means Windows refused to bind the
        // hotkey. Keep the dialog open so the user can pick a different combination.
        if (conflict is not null)
        {
            ShowStatus(conflict, isError: true);
            return;
        }

        ShowStatus("SYSTEM READY", isError: false);
        HideWindow();
    }

    private void ShowStatus(string text, bool isError)
    {
        _statusText.Text = text;
        _statusDot.Fill = isError ? DangerBrush : PrimaryButtonBrush;
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        HideWindow();
    }

    private UIElement CreateContent()
    {
        ConfigureSwitch(_startWithWindowsSwitch);
        ConfigureSwitch(_autoShareSwitch);
        ConfigureSwitch(_hideWhenNotSharingSwitch);
        ConfigureSwitch(_pinOutputSwitch);
        ConfigureSwitch(_showTaskbarIconSwitch);
        ConfigureSwitch(_showOverlaySwitch);

        _pinOutputSwitch.Toggled += PinOutputSwitch_Toggled;
        _hideWhenNotSharingSwitch.Toggled += HideWhenNotSharingSwitch_Toggled;

        var root = new Grid
        {
            Width = WindowWidth,
            Height = WindowHeight,
            Padding = new Thickness(18),
            Background = BackgroundBrush,
        };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var header = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 10,
            Margin = new Thickness(0, 0, 0, 16),
        };
        header.Children.Add(new FontIcon
        {
            FontFamily = new FontFamily("Segoe Fluent Icons"),
            Glyph = "\uE713",
            FontSize = 18,
            Foreground = WhiteBrush,
        });
        header.Children.Add(new TextBlock
        {
            Text = "Settings",
            FontSize = 22,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = WhiteBrush,
            VerticalAlignment = VerticalAlignment.Center,
        });
        root.Children.Add(header);

        var columns = new Grid
        {
            ColumnSpacing = 18,
        };
        Grid.SetRow(columns, 1);
        columns.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        columns.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(columns);

        var leftColumn = new StackPanel { Spacing = 16 };
        columns.Children.Add(leftColumn);

        leftColumn.Children.Add(CreateSectionLabel("GENERAL"));
        leftColumn.Children.Add(CreateCard(
            CreateSettingRow("Start on Login", "Launch CursorFollow automatically", _startWithWindowsSwitch),
            CreateDivider(),
            CreateSettingRow("Resume output on launch", "Resume output when a target is available", _autoShareSwitch),
            CreateDivider(),
            CreateSettingRow("Hide when not sharing", _hideWhenNotSharingSubtitle, _hideWhenNotSharingSwitch),
            CreateDivider(),
            CreateSettingRow("Pin output on top", _pinOutputSubtitle, _pinOutputSwitch)));

        leftColumn.Children.Add(CreateSectionLabel("CAPTURE QUALITY"));
        leftColumn.Children.Add(CreateCard(
            CreateQualitySegment(),
            new TextBlock
            {
                Text = "Optimization level for real-time cursor tracking and window refreshes.",
                Foreground = WhiteBrush,
                Opacity = 0.82,
                FontStyle = Windows.UI.Text.FontStyle.Italic,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 10, 0, 0),
            }));

        var rightColumn = new StackPanel { Spacing = 16 };
        Grid.SetColumn(rightColumn, 1);
        columns.Children.Add(rightColumn);

        rightColumn.Children.Add(CreateSectionLabel("HOTKEYS"));
        rightColumn.Children.Add(CreateCard(
            CreateHotkeyRow("Toggle Auto-follow", "Click, then press a shortcut", _autoFollowHotkey),
            CreateDivider(),
            CreateHotkeyRow("Toggle Output", "Click, then press a shortcut", _toggleOutputHotkey)));

        rightColumn.Children.Add(CreateSectionLabel("DISPLAY"));
        rightColumn.Children.Add(CreateCard(
            CreateOutputScalingBlock(),
            CreateDivider(),
            CreateSettingRow("Show overlay", "Display telemetry on output window", _showOverlaySwitch),
            CreateDivider(),
            CreateSettingRow("Show app in taskbar", "Keep CursorFollow windows visible in the taskbar", _showTaskbarIconSwitch)));

        rightColumn.Children.Add(CreateSectionLabel("ABOUT"));
        rightColumn.Children.Add(CreateCard(CreateAboutContent()));

        var footer = new Grid { Margin = new Thickness(0, 14, 0, 0) };
        Grid.SetRow(footer, 2);
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.Children.Add(footer);

        var status = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            VerticalAlignment = VerticalAlignment.Center,
        };
        _statusDot = new Ellipse
        {
            Width = 8,
            Height = 8,
            Fill = PrimaryButtonBrush,
            VerticalAlignment = VerticalAlignment.Center,
        };
        status.Children.Add(_statusDot);
        _statusText = new TextBlock
        {
            Text = "SYSTEM READY",
            Foreground = WhiteBrush,
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        };
        status.Children.Add(_statusText);
        footer.Children.Add(status);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
        };
        Grid.SetColumn(buttons, 1);
        buttons.Children.Add(CreateFooterButton("Cancel", SecondaryButtonBrush, WhiteBrush));
        buttons.Children.Add(CreateFooterButton("Save Changes", PrimaryButtonBrush, PrimaryButtonTextBrush));
        ((Button)buttons.Children[0]).Click += CancelButton_Click;
        ((Button)buttons.Children[1]).Click += SaveButton_Click;
        footer.Children.Add(buttons);

        return root;
    }

    private static TextBlock CreateSectionLabel(string title)
    {
        return new TextBlock
        {
            Text = title,
            Foreground = PrimaryButtonBrush,
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
            Margin = new Thickness(0, 0, 0, -8),
        };
    }

    private static Border CreateCard(params UIElement[] controls)
    {
        var stack = new StackPanel { Spacing = 0 };
        foreach (var control in controls)
        {
            stack.Children.Add(control);
        }

        return new Border
        {
            Padding = new Thickness(10),
            Background = CardBrush,
            BorderBrush = CardBorderBrush,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Child = stack,
        };
    }

    private static Border CreateDivider()
    {
        return new Border
        {
            Height = 1,
            Margin = new Thickness(0, 8, 0, 8),
            Background = DividerBrush,
            Opacity = 0.72,
        };
    }

    private static Grid CreateSettingRow(string title, string subtitle, ToggleSwitch toggle)
    {
        var row = new Grid { MinHeight = 44, ColumnSpacing = 12 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var text = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock
        {
            Text = title,
            Foreground = WhiteBrush,
            FontSize = 16,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });
        text.Children.Add(new TextBlock
        {
            Text = subtitle,
            Foreground = MutedBrush,
            FontSize = 13,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
        });
        row.Children.Add(text);

        Grid.SetColumn(toggle, 1);
        row.Children.Add(toggle);
        return row;
    }

    // Overload that takes a pre-built subtitle so callers can mutate the explanation text
    // later (used by the mutually exclusive Pin / Hide toggles).
    private static Grid CreateSettingRow(string title, TextBlock subtitle, ToggleSwitch toggle)
    {
        var row = new Grid { MinHeight = 44, ColumnSpacing = 12 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var text = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock
        {
            Text = title,
            Foreground = WhiteBrush,
            FontSize = 16,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });
        text.Children.Add(subtitle);
        row.Children.Add(text);

        Grid.SetColumn(toggle, 1);
        row.Children.Add(toggle);
        return row;
    }

    private static TextBlock CreateSubtitleBlock(string text) => new()
    {
        Text = text,
        Foreground = MutedBrush,
        FontSize = 13,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        TextWrapping = TextWrapping.Wrap,
    };

    private void PinOutputSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_syncingExclusiveToggles)
        {
            return;
        }

        if (_pinOutputSwitch.IsOn)
        {
            _syncingExclusiveToggles = true;
            _hideWhenNotSharingSwitch.IsOn = false;
            _syncingExclusiveToggles = false;
        }

        UpdateExclusiveToggleState();
    }

    private void HideWhenNotSharingSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_syncingExclusiveToggles)
        {
            return;
        }

        if (_hideWhenNotSharingSwitch.IsOn)
        {
            _syncingExclusiveToggles = true;
            _pinOutputSwitch.IsOn = false;
            _syncingExclusiveToggles = false;
        }

        UpdateExclusiveToggleState();
    }

    // "Hide when not sharing" and "Pin output on top" are mutually exclusive: pinning means the
    // output should stay visible on top, which contradicts hiding it when idle. Disable and
    // explain whichever option is blocked by the other.
    private void UpdateExclusiveToggleState()
    {
        _hideWhenNotSharingSwitch.IsEnabled = !_pinOutputSwitch.IsOn;
        _pinOutputSwitch.IsEnabled = !_hideWhenNotSharingSwitch.IsOn;

        _hideWhenNotSharingSubtitle.Text = _pinOutputSwitch.IsOn
            ? "Disabled while output is pinned on top"
            : "Hide the output window while paused";
        _pinOutputSubtitle.Text = _hideWhenNotSharingSwitch.IsOn
            ? "Disabled while “Hide when not sharing” is on"
            : "Keep output window above other windows";
    }

    private Grid CreateQualitySegment()
    {
        var segment = new Grid
        {
            Height = 34,
            Background = SegmentBackgroundBrush,
            ColumnSpacing = 0,
        };
        segment.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        segment.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        segment.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        ConfigureQualityButton(_balancedQualityButton, "Balanced");
        ConfigureQualityButton(_performanceQualityButton, "Performance");
        ConfigureQualityButton(_lowLatencyQualityButton, "Low-Latency");
        segment.Children.Add(_balancedQualityButton);
        Grid.SetColumn(_performanceQualityButton, 1);
        segment.Children.Add(_performanceQualityButton);
        Grid.SetColumn(_lowLatencyQualityButton, 2);
        segment.Children.Add(_lowLatencyQualityButton);
        return segment;
    }

    private static Grid CreateHotkeyRow(string title, string subtitle, HotkeyCaptureControl control)
    {
        var row = new Grid { MinHeight = 42, ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var text = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock
        {
            Text = title,
            Foreground = WhiteBrush,
            FontSize = 15,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });
        text.Children.Add(new TextBlock
        {
            Text = subtitle,
            Foreground = MutedBrush,
            FontSize = 13,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });
        row.Children.Add(text);

        Grid.SetColumn(control, 1);
        row.Children.Add(control);
        return row;
    }

    private Grid CreateOutputScalingBlock()
    {
        var root = new Grid { RowSpacing = 9 };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(new TextBlock
        {
            Text = "Output scaling",
            Foreground = WhiteBrush,
            FontSize = 16,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });

        var segment = new Grid
        {
            Height = 36,
            Background = SegmentBackgroundBrush,
        };
        segment.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        segment.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        segment.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        ConfigureScaleButton(_fitScaleButton, "Fit");
        ConfigureScaleButton(_fillScaleButton, "Fill");
        ConfigureScaleButton(_actualScaleButton, "Actual");
        segment.Children.Add(_fitScaleButton);
        Grid.SetColumn(_fillScaleButton, 1);
        segment.Children.Add(_fillScaleButton);
        Grid.SetColumn(_actualScaleButton, 2);
        segment.Children.Add(_actualScaleButton);

        Grid.SetRow(segment, 1);
        root.Children.Add(segment);
        return root;
    }

    private void ConfigureScaleButton(Button button, string value)
    {
        button.Content = value.ToUpperInvariant();
        button.HorizontalAlignment = HorizontalAlignment.Stretch;
        button.VerticalAlignment = VerticalAlignment.Stretch;
        button.BorderThickness = new Thickness(0);
        button.FontSize = 12;
        button.FontWeight = Microsoft.UI.Text.FontWeights.Bold;
        button.Click += (_, _) => SelectScaleMode(value);
    }

    private void SelectScaleMode(string mode)
    {
        _selectedScaleMode = mode switch
        {
            "Fill" => "Fill",
            "Actual" => "Actual",
            _ => "Fit",
        };

        UpdateQualityButton(_fitScaleButton, _selectedScaleMode == "Fit");
        UpdateQualityButton(_fillScaleButton, _selectedScaleMode == "Fill");
        UpdateQualityButton(_actualScaleButton, _selectedScaleMode == "Actual");
    }

    private static UIElement CreateAboutContent()
    {
        var stack = new StackPanel { Spacing = 6 };
        stack.Children.Add(new TextBlock
        {
            Text = "CursorFollowWin",
            Foreground = WhiteBrush,
            FontSize = 16,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });
        stack.Children.Add(new TextBlock
        {
            Text = $"Version {AppVersion()}",
            Foreground = MutedBrush,
            FontSize = 13,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        });

        var links = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 4,
            Margin = new Thickness(0, 2, 0, 0),
        };
        links.Children.Add(CreateLinkButton("Documentation", "https://github.com/LoganRupe/CursorFollow/src/branch/main/README.md"));
        links.Children.Add(CreateLinkButton("Changelog", "https://github.com/LoganRupe/CursorFollow/src/branch/main/CHANGELOG.md"));
        stack.Children.Add(links);
        return stack;
    }

    private static HyperlinkButton CreateLinkButton(string text, string url) => new()
    {
        Content = text,
        NavigateUri = new Uri(url),
        Padding = new Thickness(2, 0, 2, 0),
        FontSize = 13,
        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
    };

    private static string AppVersion()
    {
        var version = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
        return version is null ? "1.0" : $"{version.Major}.{version.Minor}";
    }

    private static Button CreateFooterButton(string text, Brush background, Brush foreground)
    {
        return new Button
        {
            Content = text,
            MinWidth = text.Length > 8 ? 126 : 80,
            Height = 36,
            Background = background,
            Foreground = foreground,
            BorderBrush = background,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
        };
    }

    private static void ConfigureSwitch(ToggleSwitch toggle)
    {
        toggle.Header = null;
        toggle.OnContent = string.Empty;
        toggle.OffContent = string.Empty;
        toggle.MinWidth = 54;
        toggle.HorizontalAlignment = HorizontalAlignment.Right;
        toggle.VerticalAlignment = VerticalAlignment.Center;
    }

    private void ConfigureQualityButton(Button button, string value)
    {
        button.HorizontalAlignment = HorizontalAlignment.Stretch;
        button.VerticalAlignment = VerticalAlignment.Stretch;
        button.BorderThickness = new Thickness(0);
        button.FontSize = 12;
        button.FontWeight = Microsoft.UI.Text.FontWeights.Bold;
        button.Click += (_, _) => SelectQuality(value);
    }

    private void HideWindow()
    {
        ShowWindow(_windowHandle, SwHide);
    }

    private void ConfigureBorderlessChrome()
    {
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.SetBorderAndTitleBar(false, false);
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
        }

        RemoveNativeWindowBorder();

        var borderColor = DwmwaSettingsBorderColor;
        DwmSetWindowAttribute(_windowHandle, DwmwaBorderColor, ref borderColor, sizeof(uint));
    }

    private void PositionNearAnchor(RectInt32? anchorBounds)
    {
        var windowId = Win32Interop.GetWindowIdFromWindow(_windowHandle);
        var displayArea = DisplayArea.GetFromWindowId(windowId, DisplayAreaFallback.Nearest);
        var workArea = displayArea.WorkArea;
        var anchor = anchorBounds ?? new RectInt32(
            workArea.X + workArea.Width - WindowWidth - 12,
            workArea.Y + workArea.Height,
            0,
            0);

        var preferredX = anchor.X + anchor.Width - WindowWidth;
        var preferredY = anchor.Y - WindowHeight - AnchorGap;
        var minX = workArea.X + 8;
        var minY = workArea.Y + 8;
        var maxX = workArea.X + workArea.Width - WindowWidth - 8;
        var maxY = workArea.Y + workArea.Height - WindowHeight - 8;
        var x = Math.Clamp(preferredX, minX, Math.Max(minX, maxX));
        var y = Math.Clamp(preferredY, minY, Math.Max(minY, maxY));

        AppWindow.Move(new PointInt32(x, y));
    }

    private void RemoveNativeWindowBorder()
    {
        var style = GetWindowLongPtr(_windowHandle, GwlStyle).ToInt64();
        style &= ~(WsCaption | WsBorder | WsDlgFrame | WsThickFrame);
        SetWindowLongPtr(_windowHandle, GwlStyle, new IntPtr(style));
        SetWindowPos(_windowHandle, IntPtr.Zero, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoZOrder | SwpFrameChanged);
    }

    private void SetTaskbarIconVisible(bool isVisible)
    {
        var exStyle = GetWindowLongPtr(_windowHandle, GwlExStyle).ToInt64();
        exStyle = isVisible
            ? (exStyle | WsExAppWindow) & ~WsExToolWindow
            : (exStyle | WsExToolWindow) & ~WsExAppWindow;

        SetWindowLongPtr(_windowHandle, GwlExStyle, new IntPtr(exStyle));
        SetWindowPos(
            _windowHandle,
            IntPtr.Zero,
            0,
            0,
            0,
            0,
            SwpNoMove | SwpNoSize | SwpNoZOrder | SwpNoActivate | SwpFrameChanged);
    }

    private void SelectQuality(string quality)
    {
        _selectedQuality = quality switch
        {
            "Performance" => "Performance",
            "Low-Latency" => "Low-Latency",
            _ => "Balanced",
        };

        UpdateQualityButton(_balancedQualityButton, _selectedQuality == "Balanced");
        UpdateQualityButton(_performanceQualityButton, _selectedQuality == "Performance");
        UpdateQualityButton(_lowLatencyQualityButton, _selectedQuality == "Low-Latency");
    }

    private string SelectedQuality()
    {
        return _selectedQuality;
    }

    private static void UpdateQualityButton(Button button, bool isSelected)
    {
        button.Background = isSelected ? AccentBrush : new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0));
        button.Foreground = isSelected ? WhiteBrush : MutedBrush;
        button.BorderBrush = isSelected ? AccentBrush : new SolidColorBrush(Windows.UI.Color.FromArgb(0, 0, 0, 0));
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int dwAttribute, ref uint pvAttribute, int cbAttribute);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int x,
        int y,
        int cx,
        int cy,
        uint flags);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
}