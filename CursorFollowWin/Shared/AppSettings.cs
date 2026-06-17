using System.Text.Json;
using System.Text.Json.Serialization;

namespace CursorFollowWin;

public sealed record AppSettings
{
    public bool StartWithWindows { get; init; }
    public bool AutoShareOnLaunch { get; init; }
    public bool HideWhenNotSharing { get; init; }
    public bool PinOutputOnTop { get; init; }
    public bool ShowTaskbarIcon { get; init; }
    public string CaptureQuality { get; init; } = "Balanced";
    public string OutputScaleMode { get; init; } = "Fit";
    public WindowFilterMode WindowFilterMode { get; init; } = WindowFilterMode.All;
    public string[] IncludeWindowIdentities { get; init; } = Array.Empty<string>();
    public string[] ExcludeWindowIdentities { get; init; } = Array.Empty<string>();
    public string AutoFollowHotkey { get; init; } = "Ctrl+Alt+F";
    public string ToggleOutputHotkey { get; init; } = "Ctrl+Alt+S";
}

[JsonSourceGenerationOptions(WriteIndented = true)]
[JsonSerializable(typeof(AppSettings))]
internal sealed partial class AppSettingsJsonContext : JsonSerializerContext;

public static class SettingsStore
{
    private static readonly string SettingsDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "CursorFollowWin");

    private static readonly string SettingsPath = Path.Combine(SettingsDirectory, "settings.json");

    public static AppSettings Current { get; private set; } = new();

    public static void Load()
    {
        if (!File.Exists(SettingsPath))
        {
            Current = new AppSettings();
            return;
        }

        try
        {
            var json = File.ReadAllText(SettingsPath);
            var loaded = JsonSerializer.Deserialize(json, AppSettingsJsonContext.Default.AppSettings) ?? new AppSettings();
            Current = Normalize(loaded);
        }
        catch (JsonException)
        {
            Current = new AppSettings();
        }
        catch (IOException)
        {
            Current = new AppSettings();
        }
    }

    // Settings files written before a field existed deserialize that field as null (System.Text.Json
    // does not apply property initializers for absent members). Replace null/blank values with the
    // current defaults so upgrading users keep working hotkeys, scaling, and filter lists.
    public static AppSettings Normalize(AppSettings settings)
    {
        var defaults = new AppSettings();
        return settings with
        {
            CaptureQuality = Fallback(settings.CaptureQuality, defaults.CaptureQuality),
            OutputScaleMode = Fallback(settings.OutputScaleMode, defaults.OutputScaleMode),
            AutoFollowHotkey = settings.AutoFollowHotkey ?? defaults.AutoFollowHotkey,
            ToggleOutputHotkey = settings.ToggleOutputHotkey ?? defaults.ToggleOutputHotkey,
            IncludeWindowIdentities = settings.IncludeWindowIdentities ?? defaults.IncludeWindowIdentities,
            ExcludeWindowIdentities = settings.ExcludeWindowIdentities ?? defaults.ExcludeWindowIdentities,
        };

        static string Fallback(string? value, string fallback) =>
            string.IsNullOrWhiteSpace(value) ? fallback : value;
    }

    public static void Save(AppSettings settings)
    {
        Directory.CreateDirectory(SettingsDirectory);
        var json = JsonSerializer.Serialize(settings, AppSettingsJsonContext.Default.AppSettings);
        File.WriteAllText(SettingsPath, json);
        Current = settings;
    }
}