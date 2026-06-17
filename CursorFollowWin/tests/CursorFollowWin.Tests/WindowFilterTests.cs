using Xunit;

namespace CursorFollowWin.Tests;

public class WindowFilterTests
{
    private static TrackedWindow Window(string packageFamilyName = "", string processPath = "", string appName = "App") =>
        new(
            Handle: 1,
            Title: "Title",
            AppName: appName,
            ProcessPath: processPath,
            PackageFamilyName: packageFamilyName,
            ProcessId: 100,
            Width: 800,
            Height: 600);

    private static AppSettings Settings(WindowFilterMode mode, string[]? include = null, string[]? exclude = null) =>
        new()
        {
            WindowFilterMode = mode,
            IncludeWindowIdentities = include ?? [],
            ExcludeWindowIdentities = exclude ?? [],
        };

    [Fact]
    public void AllMode_AllowsEveryWindow()
    {
        var window = Window(processPath: @"C:\apps\thing.exe");
        Assert.True(WindowFilter.IsAllowed(window, Settings(WindowFilterMode.All)));
    }

    [Fact]
    public void ExcludeMode_BlocksListedIdentity_AllowsOthers()
    {
        var blocked = Window(processPath: @"C:\apps\blocked.exe");
        var allowed = Window(processPath: @"C:\apps\allowed.exe");
        var settings = Settings(WindowFilterMode.Exclude, exclude: [@"C:\apps\blocked.exe"]);

        Assert.False(WindowFilter.IsAllowed(blocked, settings));
        Assert.True(WindowFilter.IsAllowed(allowed, settings));
    }

    [Fact]
    public void IncludeMode_AllowsOnlyListedIdentity()
    {
        var approved = Window(processPath: @"C:\apps\approved.exe");
        var other = Window(processPath: @"C:\apps\other.exe");
        var settings = Settings(WindowFilterMode.Include, include: [@"C:\apps\approved.exe"]);

        Assert.True(WindowFilter.IsAllowed(approved, settings));
        Assert.False(WindowFilter.IsAllowed(other, settings));
    }

    [Fact]
    public void Matching_IsCaseInsensitive()
    {
        var window = Window(processPath: @"C:\Apps\Thing.exe");
        var settings = Settings(WindowFilterMode.Exclude, exclude: [@"c:\apps\thing.exe"]);

        Assert.False(WindowFilter.IsAllowed(window, settings));
    }

    [Fact]
    public void Filtering_UsesPackageFamilyNameAsIdentityWhenPresent()
    {
        var packaged = Window(packageFamilyName: "Contoso.App_8wekyb3d8bbwe", processPath: @"C:\apps\thing.exe");
        var settings = Settings(WindowFilterMode.Include, include: ["Contoso.App_8wekyb3d8bbwe"]);

        Assert.True(WindowFilter.IsAllowed(packaged, settings));
    }
}
