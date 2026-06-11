using System.Text.Json;
using System.Text.Json.Serialization;

namespace CursorFollowWin_App;

public sealed record AppSettings
{
    public bool StartWithWindows { get; init; }
    public bool AutoShareOnLaunch { get; init; }
    public bool HideWhenNotSharing { get; init; }
    public bool PinOutputOnTop { get; init; }
    public bool ShowTaskbarIcon { get; init; }
    public bool ShowOverlay { get; init; } = true;
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

internal static class SettingsStore
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
            Current = JsonSerializer.Deserialize(json, AppSettingsJsonContext.Default.AppSettings) ?? new AppSettings();
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

    public static void Save(AppSettings settings)
    {
        Directory.CreateDirectory(SettingsDirectory);
        var json = JsonSerializer.Serialize(settings, AppSettingsJsonContext.Default.AppSettings);
        File.WriteAllText(SettingsPath, json);
        Current = settings;
    }
}