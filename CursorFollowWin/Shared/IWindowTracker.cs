namespace CursorFollowWin;

/// <summary>
/// Abstraction over Win32 window enumeration and foreground/cursor probing so follow and panel
/// logic can be exercised with fakes. The production implementation is
/// <c>CursorFollowWin.Capture.WindowTracker</c>.
/// </summary>
public interface IWindowTracker
{
    WindowRefreshDiagnostics LastRefreshDiagnostics { get; }

    IReadOnlyList<TrackedWindow> RefreshWindows();

    TrackedWindow? GetForegroundWindowCandidate();

    TrackedWindow? GetCursorWindowCandidate();

    bool IsAllowed(TrackedWindow window, AppSettings settings);
}
