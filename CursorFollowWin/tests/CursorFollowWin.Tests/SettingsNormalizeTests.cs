using Xunit;

namespace CursorFollowWin.Tests;

public class SettingsNormalizeTests
{
    // Reproduces the upgrade bug: settings written before a field existed deserialize that field as
    // null because System.Text.Json does not run property initializers for absent members. Normalize
    // must restore defaults so hotkeys, scaling, and filter lists keep working after an upgrade.
    [Fact]
    public void Normalize_NullStrings_AreReplacedWithDefaults()
    {
        var defaults = new AppSettings();
        var fromOldFile = new AppSettings
        {
            CaptureQuality = null!,
            OutputScaleMode = null!,
            AutoFollowHotkey = null!,
            ToggleOutputHotkey = null!,
            IncludeWindowIdentities = null!,
            ExcludeWindowIdentities = null!,
        };

        var normalized = SettingsStore.Normalize(fromOldFile);

        Assert.Equal(defaults.CaptureQuality, normalized.CaptureQuality);
        Assert.Equal(defaults.OutputScaleMode, normalized.OutputScaleMode);
        Assert.Equal(defaults.AutoFollowHotkey, normalized.AutoFollowHotkey);
        Assert.Equal(defaults.ToggleOutputHotkey, normalized.ToggleOutputHotkey);
        Assert.NotNull(normalized.IncludeWindowIdentities);
        Assert.NotNull(normalized.ExcludeWindowIdentities);
        Assert.Empty(normalized.IncludeWindowIdentities);
        Assert.Empty(normalized.ExcludeWindowIdentities);
    }

    [Fact]
    public void Normalize_BlankStrings_AreReplacedWithDefaults()
    {
        var normalized = SettingsStore.Normalize(new AppSettings { CaptureQuality = "   ", OutputScaleMode = "" });

        Assert.Equal("Balanced", normalized.CaptureQuality);
        Assert.Equal("Fit", normalized.OutputScaleMode);
    }

    [Fact]
    public void Normalize_RealValues_ArePreserved()
    {
        var settings = new AppSettings
        {
            CaptureQuality = "Performance",
            OutputScaleMode = "Fill",
            AutoFollowHotkey = "Ctrl+Shift+A",
            WindowFilterMode = WindowFilterMode.Include,
            IncludeWindowIdentities = [@"C:\apps\thing.exe"],
        };

        var normalized = SettingsStore.Normalize(settings);

        Assert.Equal("Performance", normalized.CaptureQuality);
        Assert.Equal("Fill", normalized.OutputScaleMode);
        Assert.Equal("Ctrl+Shift+A", normalized.AutoFollowHotkey);
        Assert.Equal(WindowFilterMode.Include, normalized.WindowFilterMode);
        Assert.Equal([@"C:\apps\thing.exe"], normalized.IncludeWindowIdentities);
    }
}
