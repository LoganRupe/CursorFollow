using System.Runtime.InteropServices;

namespace CursorFollowWin;

internal sealed class TrayIconService : IDisposable
{
    private const int WmUser = 0x0400;
    private const int WmTrayIcon = WmUser + 1;
    private const int WmLButtonUp = 0x0202;
    private const int NimAdd = 0x00000000;
    private const int NimDelete = 0x00000002;
    private const int NifMessage = 0x00000001;
    private const int NifIcon = 0x00000002;
    private const int NifTip = 0x00000004;
    private const int ImageIcon = 1;
    private const int LrLoadFromFile = 0x00000010;
    private const int LrDefaultSize = 0x00000040;

    private readonly Action _showPanel;
    private readonly WindowProcedure _windowProcedure;
    private readonly IntPtr _messageWindow;
    private readonly IntPtr _iconHandle;

    public TrayIconService(
        Action showPanel,
        Action showOutput,
        Action hideOutput,
        Action showSettings,
        Action quit)
    {
        _showPanel = showPanel;
        _windowProcedure = WndProc;
        _messageWindow = CreateMessageWindow(_windowProcedure);
        _iconHandle = LoadTrayIcon();

        var data = CreateNotifyIconData();
        Shell_NotifyIcon(NimAdd, ref data);
    }

    public void Dispose()
    {
        var data = CreateNotifyIconData();
        Shell_NotifyIcon(NimDelete, ref data);

        if (_iconHandle != IntPtr.Zero)
        {
            DestroyIcon(_iconHandle);
        }

        if (_messageWindow != IntPtr.Zero)
        {
            DestroyWindow(_messageWindow);
        }
    }

    private IntPtr WndProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == WmTrayIcon && lParam.ToInt32() == WmLButtonUp)
        {
            _showPanel();
            return IntPtr.Zero;
        }

        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    private NotifyIconData CreateNotifyIconData()
    {
        return new NotifyIconData
        {
            cbSize = Marshal.SizeOf<NotifyIconData>(),
            hWnd = _messageWindow,
            uID = 1,
            uFlags = NifMessage | NifIcon | NifTip,
            uCallbackMessage = WmTrayIcon,
            hIcon = _iconHandle,
            szTip = "CursorFollowWin",
        };
    }

    private static IntPtr CreateMessageWindow(WindowProcedure windowProcedure)
    {
        var className = $"CursorFollowTrayWindow-{Guid.NewGuid():N}";
        var windowClass = new WindowClass
        {
            cbSize = Marshal.SizeOf<WindowClass>(),
            lpfnWndProc = windowProcedure,
            lpszClassName = className,
        };

        RegisterClassEx(ref windowClass);
        return CreateWindowEx(0, className, string.Empty, 0, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
    }

    private static IntPtr LoadTrayIcon()
    {
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
        if (File.Exists(iconPath))
        {
            var icon = LoadImage(IntPtr.Zero, iconPath, ImageIcon, 0, 0, LrLoadFromFile | LrDefaultSize);
            if (icon != IntPtr.Zero)
            {
                return icon;
            }
        }

        return LoadIcon(IntPtr.Zero, new IntPtr(32512));
    }

    private delegate IntPtr WindowProcedure(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        public int cbSize;
        public uint style;
        [MarshalAs(UnmanagedType.FunctionPtr)]
        public WindowProcedure lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public int cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;
        public uint dwState;
        public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern bool Shell_NotifyIcon(int dwMessage, ref NotifyIconData lpData);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassEx(ref WindowClass lpwcx);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(
        uint dwExStyle,
        string lpClassName,
        string lpWindowName,
        uint dwStyle,
        int x,
        int y,
        int nWidth,
        int nHeight,
        IntPtr hWndParent,
        IntPtr hMenu,
        IntPtr hInstance,
        IntPtr lpParam);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyWindow(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadImage(IntPtr hInst, string name, int type, int cx, int cy, int fuLoad);

    [DllImport("user32.dll")]
    private static extern IntPtr LoadIcon(IntPtr hInstance, IntPtr lpIconName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);
}