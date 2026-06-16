using Microsoft.Extensions.Logging;
using System.Runtime.InteropServices;

namespace CursorFollowWin;

/// <summary>
/// Registers global system hotkeys through a message-only window and dispatches them to
/// app actions. Mirrors the lightweight Win32 message-window pattern used by
/// <see cref="TrayIconService"/> rather than taking a third-party dependency.
/// </summary>
internal sealed class HotkeyService : IDisposable
{
    private const int WmHotkey = 0x0312;
    private const uint ModNoRepeat = 0x4000;

    private const int IdAutoFollow = 1;
    private const int IdToggleOutput = 2;

    private readonly Action _toggleAutoFollow;
    private readonly Action _toggleOutput;
    private readonly WindowProcedure _windowProcedure;
    private readonly IntPtr _messageWindow;
    private readonly HashSet<int> _registeredIds = new();
    private bool _disposed;

    public HotkeyService(Action toggleAutoFollow, Action toggleOutput)
    {
        _toggleAutoFollow = toggleAutoFollow;
        _toggleOutput = toggleOutput;
        _windowProcedure = WndProc;
        _messageWindow = CreateMessageWindow(_windowProcedure);
    }

    /// <summary>
    /// Re-registers both hotkeys. Returns <c>null</c> on success, or a user-facing message
    /// listing the bindings Windows refused because another app already owns them.
    /// </summary>
    public string? ApplyBindings(Hotkey autoFollow, Hotkey toggleOutput)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        UnregisterAll();

        var conflicts = new List<string>();
        if (!TryRegister(IdAutoFollow, autoFollow))
        {
            conflicts.Add($"Toggle Auto-follow ({autoFollow.Format()})");
        }

        if (!TryRegister(IdToggleOutput, toggleOutput))
        {
            conflicts.Add($"Toggle Output ({toggleOutput.Format()})");
        }

        return conflicts.Count == 0
            ? null
            : $"In use by another app: {string.Join(", ", conflicts)}";
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        UnregisterAll();

        if (_messageWindow != IntPtr.Zero)
        {
            DestroyWindow(_messageWindow);
        }
    }

    private bool TryRegister(int id, Hotkey hotkey)
    {
        // An empty/invalid binding is "nothing to register" rather than a conflict.
        if (!hotkey.IsValid)
        {
            AppLog.Hotkeys.LogInformation("No valid binding for hotkey id {Id}; leaving it unregistered.", id);
            return true;
        }

        if (RegisterHotKey(_messageWindow, id, (uint)hotkey.Modifiers | ModNoRepeat, hotkey.VirtualKey))
        {
            _registeredIds.Add(id);
            AppLog.Hotkeys.LogInformation("Registered hotkey {Hotkey} (id {Id}).", hotkey.Format(), id);
            return true;
        }

        AppLog.Hotkeys.LogWarning("Failed to register hotkey {Hotkey} (id {Id}); already in use.", hotkey.Format(), id);
        return false;
    }

    private void UnregisterAll()
    {
        foreach (var id in _registeredIds)
        {
            UnregisterHotKey(_messageWindow, id);
        }

        _registeredIds.Clear();
    }

    private IntPtr WndProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == WmHotkey)
        {
            switch (wParam.ToInt32())
            {
                case IdAutoFollow:
                    _toggleAutoFollow();
                    return IntPtr.Zero;
                case IdToggleOutput:
                    _toggleOutput();
                    return IntPtr.Zero;
            }
        }

        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    private static IntPtr CreateMessageWindow(WindowProcedure windowProcedure)
    {
        var className = $"CursorFollowHotkeyWindow-{Guid.NewGuid():N}";
        var windowClass = new WindowClass
        {
            cbSize = Marshal.SizeOf<WindowClass>(),
            lpfnWndProc = windowProcedure,
            lpszClassName = className,
        };

        RegisterClassEx(ref windowClass);
        return CreateWindowEx(0, className, string.Empty, 0, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
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

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

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
}
