namespace CursorFollowWin;

public sealed record TrackedWindow(
    IntPtr Handle,
    string Title,
    string AppName,
    string ProcessPath,
    string PackageFamilyName,
    int ProcessId,
    int Width,
    int Height)
{
    // Stable identity for filtering: packaged family name when Windows exposes it,
    // otherwise the executable path, falling back to the process/app name.
    public string Identity => !string.IsNullOrWhiteSpace(PackageFamilyName)
        ? PackageFamilyName
        : string.IsNullOrWhiteSpace(ProcessPath)
            ? AppName
            : ProcessPath;

    public string DisplayName => string.IsNullOrWhiteSpace(AppName) ? Title : $"{Title} - {AppName}";

    public string Detail => $"{AppName} | {Width}x{Height}";

    public string SizeLabel => $"{Width:N0}x{Height:N0}";
}

public sealed record WindowRefreshDiagnostics(int ShownCount, int OmittedCount, string Summary);

public enum WindowFilterMode
{
    All,
    Exclude,
    Include,
}