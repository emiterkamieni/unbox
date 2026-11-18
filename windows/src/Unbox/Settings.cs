using System.Text.Json;
using System.Text.Json.Serialization;

namespace Unbox;

/// <summary>User settings in %AppData%\unbox\settings.json.</summary>
public sealed class Settings
{
    public bool FreeSpace { get; set; } = true;
    public int RefreshMinutes { get; set; } = 5;
    public string SortOrder { get; set; } = "name";
    public string Language { get; set; } = "system";
    public bool NotifyAboutUpdates { get; set; } = true;
    public DateTime? LastUpdateCheck { get; set; }
    public string? NotifiedVersion { get; set; }

    /// <summary>Demo mode: never written to disk.</summary>
    [JsonIgnore] public bool IsTransient { get; init; }

    private static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "unbox", "settings.json");

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath)) return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException) { }
        return new Settings();
    }

    public void Save()
    {
        if (IsTransient) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Options));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }
}
