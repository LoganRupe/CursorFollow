namespace CursorFollowWin_App;

public sealed record TrackedWindow(
    IntPtr Handle,
    string Title,
    string AppName,
    string ProcessPath,
    int ProcessId,
    int Width,
    int Height)
{
    public string Identity => string.IsNullOrWhiteSpace(ProcessPath) ? AppName : ProcessPath;

    public string DisplayName => string.IsNullOrWhiteSpace(AppName) ? Title : $"{Title} - {AppName}";

    public string Detail => $"{AppName} | {Width}x{Height}";

    public string SizeLabel => $"{Width:N0}x{Height:N0}";
}

public enum WindowFilterMode
{
    All,
    Exclude,
    Include,
}