using Microsoft.Win32;

namespace CursorFollowWin_App;

/// <summary>
/// Registers the app to launch on Windows sign-in via the per-user <c>Run</c> key.
/// Unpackaged WinUI apps have no StartupTask manifest, so the registry Run key is the
/// appropriate mechanism. Registration is best-effort: a failure to write the key must
/// never prevent the app from starting.
/// </summary>
internal static class StartupRegistration
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "CursorFollowWin";

    /// <summary>
    /// Brings the Run key into line with the desired state. When enabling, the value is
    /// rewritten to the current executable path so a moved/reinstalled binary self-heals.
    /// </summary>
    public static void Apply(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
                ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (key is null)
            {
                return;
            }

            if (enabled)
            {
                var executablePath = Environment.ProcessPath;
                if (!string.IsNullOrEmpty(executablePath))
                {
                    key.SetValue(ValueName, $"\"{executablePath}\"");
                }
            }
            else
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or System.Security.SecurityException)
        {
            // Best-effort: the toggle is persisted in settings regardless of registry success.
        }
    }
}
