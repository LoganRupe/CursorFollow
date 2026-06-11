using Microsoft.Extensions.Logging;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace CursorFollowWin_App;

internal sealed class WindowTracker
{
    private const int DwmwaCloaked = 14;
    private const int GwlExStyle = -20;
    private const uint GaRoot = 2;
    private const uint WsExToolWindow = 0x00000080;
    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const int AppModelErrorNoPackage = 15700;

    private readonly int _currentProcessId = Environment.ProcessId;
    private readonly IntPtr _shellWindow = GetShellWindow();
    private readonly Dictionary<string, int> _omittedReasons = new(StringComparer.OrdinalIgnoreCase);

    public WindowRefreshDiagnostics LastRefreshDiagnostics { get; private set; } = new(0, 0, "No refresh yet");

    public IReadOnlyList<TrackedWindow> RefreshWindows() => EnumerateWindows().ToArray();

    public TrackedWindow? GetForegroundWindowCandidate()
    {
        var handle = GetForegroundWindow();
        return TryCreateWindow(handle, out var window) ? window : null;
    }

    public TrackedWindow? GetCursorWindowCandidate()
    {
        if (!GetCursorPos(out var point))
        {
            return null;
        }

        var handle = WindowFromPoint(point);
        if (handle == IntPtr.Zero)
        {
            return null;
        }

        var root = GetAncestor(handle, GaRoot);
        return TryCreateWindow(root == IntPtr.Zero ? handle : root, out var window) ? window : null;
    }

    public bool IsAllowed(TrackedWindow window, AppSettings settings)
    {
        var identity = window.Identity;
        return settings.WindowFilterMode switch
        {
            WindowFilterMode.Exclude => !settings.ExcludeWindowIdentities.Contains(identity, StringComparer.OrdinalIgnoreCase),
            WindowFilterMode.Include => settings.IncludeWindowIdentities.Contains(identity, StringComparer.OrdinalIgnoreCase),
            _ => true,
        };
    }

    private IEnumerable<TrackedWindow> EnumerateWindows()
    {
        var windows = new List<TrackedWindow>();
        _omittedReasons.Clear();

        EnumWindows((handle, _) =>
        {
            if (TryCreateWindow(handle, out var window, trackOmission: true))
            {
                windows.Add(window);
            }

            return true;
        }, IntPtr.Zero);

        var omitted = _omittedReasons.Values.Sum();
        LastRefreshDiagnostics = new WindowRefreshDiagnostics(
            windows.Count,
            omitted,
            omitted == 0
                ? $"{windows.Count} capturable windows found"
                : $"{windows.Count} shown, {omitted} hidden or filtered ({FormatTopOmissions()})");

        AppLog.WindowTracker.LogInformation("Window refresh: {Summary}", LastRefreshDiagnostics.Summary);

        return windows
            .OrderBy(window => window.AppName, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(window => window.Title, StringComparer.CurrentCultureIgnoreCase);
    }

    private bool TryCreateWindow(IntPtr handle, out TrackedWindow window, bool trackOmission = false)
    {
        window = default!;

        if (handle == IntPtr.Zero)
        {
            TrackOmission(trackOmission, "no handle");
            return false;
        }

        if (handle == _shellWindow || !IsWindowVisible(handle) || IsIconic(handle) || IsCloaked(handle) || IsToolWindow(handle))
        {
            TrackOmission(trackOmission, "hidden/system");
            return false;
        }

        var title = GetWindowTitle(handle);
        if (string.IsNullOrWhiteSpace(title) || string.Equals(title, WindowsGraphicsCaptureController.OutputWindowTitle, StringComparison.OrdinalIgnoreCase))
        {
            TrackOmission(trackOmission, "untitled/output");
            return false;
        }

        if (!GetWindowRect(handle, out var rect))
        {
            TrackOmission(trackOmission, "no bounds");
            return false;
        }

        var width = rect.Right - rect.Left;
        var height = rect.Bottom - rect.Top;
        if (width < 80 || height < 80)
        {
            TrackOmission(trackOmission, "too small");
            return false;
        }

        GetWindowThreadProcessId(handle, out var processId);
        if (processId == 0 || processId == _currentProcessId)
        {
            TrackOmission(trackOmission, "own/processless");
            return false;
        }

        var processPath = GetProcessPath(processId);
        var packageFamilyName = GetPackageFamilyName(processId);
        var appName = GetAppName(processId, processPath);
        if (IsSystemSurface(appName, processPath, title))
        {
            TrackOmission(trackOmission, "system surface");
            return false;
        }

        window = new TrackedWindow(handle, title, appName, processPath, packageFamilyName, (int)processId, width, height);
        return true;
    }

    private string FormatTopOmissions() => string.Join(", ", _omittedReasons
        .OrderByDescending(reason => reason.Value)
        .ThenBy(reason => reason.Key, StringComparer.OrdinalIgnoreCase)
        .Take(3)
        .Select(reason => $"{reason.Value} {reason.Key}"));

    private void TrackOmission(bool shouldTrack, string reason)
    {
        if (!shouldTrack)
        {
            return;
        }

        _omittedReasons[reason] = _omittedReasons.TryGetValue(reason, out var count) ? count + 1 : 1;
    }

    private static bool IsCloaked(IntPtr handle)
    {
        var result = DwmGetWindowAttribute(handle, DwmwaCloaked, out int cloaked, Marshal.SizeOf<int>());
        return result == 0 && cloaked != 0;
    }

    private static bool IsToolWindow(IntPtr handle)
    {
        var style = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
        return (style & WsExToolWindow) != 0;
    }

    private static string GetWindowTitle(IntPtr handle)
    {
        var length = GetWindowTextLength(handle);
        if (length <= 0)
        {
            return string.Empty;
        }

        var builder = new StringBuilder(length + 1);
        GetWindowText(handle, builder, builder.Capacity);
        return builder.ToString().Trim();
    }

    private static string GetProcessPath(uint processId)
    {
        var processHandle = OpenProcess(ProcessQueryLimitedInformation, false, processId);
        if (processHandle == IntPtr.Zero)
        {
            return string.Empty;
        }

        try
        {
            var builder = new StringBuilder(1024);
            var size = builder.Capacity;
            return QueryFullProcessImageName(processHandle, 0, builder, ref size) ? builder.ToString() : string.Empty;
        }
        finally
        {
            CloseHandle(processHandle);
        }
    }

    private static string GetPackageFamilyName(uint processId)
    {
        var processHandle = OpenProcess(ProcessQueryLimitedInformation, false, processId);
        if (processHandle == IntPtr.Zero)
        {
            return string.Empty;
        }

        try
        {
            var length = 0u;
            var result = GetPackageFamilyName(processHandle, ref length, null);
            if (result == AppModelErrorNoPackage || length == 0)
            {
                return string.Empty;
            }

            var builder = new StringBuilder((int)length);
            result = GetPackageFamilyName(processHandle, ref length, builder);
            return result == 0 ? builder.ToString() : string.Empty;
        }
        finally
        {
            CloseHandle(processHandle);
        }
    }

    private static string GetAppName(uint processId, string processPath)
    {
        if (!string.IsNullOrWhiteSpace(processPath))
        {
            return Path.GetFileNameWithoutExtension(processPath);
        }

        try
        {
            using var process = Process.GetProcessById((int)processId);
            return process.ProcessName;
        }
        catch (ArgumentException)
        {
            return "Unknown app";
        }
        catch (InvalidOperationException)
        {
            return "Unknown app";
        }
    }

    private static bool IsSystemSurface(string appName, string processPath, string title)
    {
        var processFile = Path.GetFileName(processPath);
        var blockedNames = new[]
        {
            "CursorFollowWin.App.exe",
            "CursorFollowWin.exe",
            "dwm.exe",
            "explorer.exe",
            "ShellExperienceHost.exe",
            "StartMenuExperienceHost.exe",
            "SystemSettings.exe",
            "TextInputHost.exe",
        };

        if (blockedNames.Contains(processFile, StringComparer.OrdinalIgnoreCase))
        {
            return true;
        }

        var blockedTitles = new[] { "Program Manager", "Windows Input Experience" };
        return blockedTitles.Contains(title, StringComparer.OrdinalIgnoreCase) || string.Equals(appName, "CursorFollowWin.App", StringComparison.OrdinalIgnoreCase);
    }

    private delegate bool EnumWindowsCallback(IntPtr hwnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out Point lpPoint);

    [DllImport("user32.dll")]
    private static extern IntPtr WindowFromPoint(Point point);

    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);

    [DllImport("user32.dll")]
    private static extern IntPtr GetShellWindow();

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect lpRect);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint processAccess, bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder exeName, ref int size);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetPackageFamilyName(IntPtr process, ref uint packageFamilyNameLength, StringBuilder? packageFamilyName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);
}