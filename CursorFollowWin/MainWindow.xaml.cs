using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;
using Windows.Graphics;

namespace CursorFollowWin;

public sealed partial class MainWindow : Window
{
    private const int GwlExStyle = -20;
    private const int SwHide = 0;
    private const int SwShow = 5;
    private const int SwShowNoActivate = 4;
    private const int SwMinimize = 6;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpFrameChanged = 0x0020;
    private const long WsExToolWindow = 0x00000080L;
    private const long WsExAppWindow = 0x00040000L;

    private static readonly IntPtr HwndTopMost = new(-1);
    private static readonly IntPtr HwndNoTopMost = new(-2);

    private readonly IntPtr _windowHandle;
    private AppSettings _settings;
    private bool _isVisible;
    private bool _showTaskbarIcon;

    public MainWindow(AppSettings settings)
    {
        InitializeComponent();
        _settings = settings;

        Title = WindowsGraphicsCaptureController.OutputWindowTitle;
        _windowHandle = WinRT.Interop.WindowNative.GetWindowHandle(this);

        AppWindow.SetIcon("Assets/AppIcon.ico");
        SizeToContent(1280, 720);
        SetTaskbarIconVisible(settings.ShowTaskbarIcon);

        RootFrame.Navigate(typeof(MainPage));

        if (RootFrame.Content is MainPage mainPage)
        {
            mainPage.InitializeWindowHandle(_windowHandle);
            mainPage.OutputStateChanged += (_, _) => ApplyOutputVisibilityPolicy();
            mainPage.ContentSizeChanged += SizeToContent;
        }
    }

    public event EventHandler? OutputStateChanged;

    public MainPage? OutputPage => RootFrame.Content as MainPage;

    public bool IsOutputVisible => _isVisible;

    public void ShowOutput(bool activate = true)
    {
        ShowWindow(_windowHandle, activate ? SwShow : SwShowNoActivate);
        _isVisible = true;
        if (activate)
        {
            Activate();
        }

        OutputStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void HideOutput()
    {
        ShowWindow(_windowHandle, _showTaskbarIcon ? SwMinimize : SwHide);
        _isVisible = false;
        OutputStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ApplySettings(AppSettings settings)
    {
        _settings = settings;
        OutputPage?.ApplyCaptureQuality(settings.CaptureQuality);
        OutputPage?.ApplyOutputScaleMode(settings.OutputScaleMode);
        SetTaskbarIconVisible(settings.ShowTaskbarIcon);
        SetTopMost(settings.PinOutputOnTop);
        ApplyOutputVisibilityPolicy();
        OutputStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void DisposeCapture()
    {
        OutputPage?.DisposeCapture();
    }

    private void SetTopMost(bool isTopMost)
    {
        var insertAfter = isTopMost ? HwndTopMost : HwndNoTopMost;
        SetWindowPos(
            _windowHandle,
            insertAfter,
            0,
            0,
            0,
            0,
            SwpNoMove | SwpNoSize | SwpNoActivate);
    }

    // Match the window to the captured content's aspect ratio (bounded to a reasonable size) so
    // the output fills the window edge-to-edge with no letterbox/pillarbox bars.
    private void SizeToContent(int contentWidth, int contentHeight)
    {
        if (contentWidth <= 0 || contentHeight <= 0)
        {
            return;
        }

        const double maxWidth = 1280;
        const double maxHeight = 900;
        var scale = Math.Min(maxWidth / contentWidth, maxHeight / contentHeight);
        var width = Math.Max(1, (int)Math.Round(contentWidth * scale));
        var height = Math.Max(1, (int)Math.Round(contentHeight * scale));

        AppWindow.Resize(new SizeInt32(width, height));
    }

    private void ApplyOutputVisibilityPolicy()
    {
        if (_settings.HideWhenNotSharing && OutputPage?.IsCapturing != true && _isVisible)
        {
            HideOutput();
        }
    }

    public void SetTaskbarIconVisible(bool isVisible)
    {
        _showTaskbarIcon = isVisible;

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

        if (!isVisible && !_isVisible)
        {
            ShowWindow(_windowHandle, SwHide);
        }
        else if (isVisible && !_isVisible)
        {
            ShowWindow(_windowHandle, SwMinimize);
        }
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

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
