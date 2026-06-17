namespace CursorFollowWin;

/// <summary>
/// Pure filter-mode logic that decides whether a tracked window may be followed under the current
/// settings. Kept free of Win32 so it can be unit-tested with plain <see cref="TrackedWindow"/>
/// values; the window tracker delegates to it.
/// </summary>
public static class WindowFilter
{
    public static bool IsAllowed(TrackedWindow window, AppSettings settings)
    {
        var identity = window.Identity;
        return settings.WindowFilterMode switch
        {
            WindowFilterMode.Exclude => !settings.ExcludeWindowIdentities.Contains(identity, StringComparer.OrdinalIgnoreCase),
            WindowFilterMode.Include => settings.IncludeWindowIdentities.Contains(identity, StringComparer.OrdinalIgnoreCase),
            _ => true,
        };
    }
}
