using Xunit;

namespace CursorFollowWin.Tests;

public class TrackedWindowTests
{
    private static TrackedWindow Window(string pfn, string path, string appName) =>
        new(Handle: 1, Title: "Doc", AppName: appName, ProcessPath: path, PackageFamilyName: pfn, ProcessId: 1, Width: 800, Height: 600);

    [Fact]
    public void Identity_PrefersPackageFamilyName()
    {
        var window = Window("Contoso.App_8wekyb3d8bbwe", @"C:\apps\thing.exe", "thing");
        Assert.Equal("Contoso.App_8wekyb3d8bbwe", window.Identity);
    }

    [Fact]
    public void Identity_FallsBackToProcessPath_WhenNoPackage()
    {
        var window = Window("", @"C:\apps\thing.exe", "thing");
        Assert.Equal(@"C:\apps\thing.exe", window.Identity);
    }

    [Fact]
    public void Identity_FallsBackToAppName_WhenNoPackageOrPath()
    {
        var window = Window("", "", "thing");
        Assert.Equal("thing", window.Identity);
    }

    [Fact]
    public void DisplayName_CombinesTitleAndApp()
    {
        var window = Window("", "", "thing");
        Assert.Equal("Doc - thing", window.DisplayName);
    }
}
