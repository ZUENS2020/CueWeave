using System.Text.Json;
using CueWeave.WinUI.Models;

namespace CueWeave.WinUI.Services;

public static class LocalSettingsStore
{
    public static string ConfigPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CueWeave", "settings.json");

    public static LocalSettings Load(string? path = null)
    {
        path ??= ConfigPath;
        try {
            if (!File.Exists(path)) return new();
            var settings = JsonSerializer.Deserialize(
                File.ReadAllBytes(path), CueJsonContext.Default.LocalSettings) ?? new();
            settings.MigrateLegacyModelDefaults();
            return settings;
        } catch { return new(); }
    }

    public static void Save(LocalSettings settings, string? path = null)
    {
        path ??= ConfigPath;
        var directory = Path.GetDirectoryName(path)!;
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, $"settings.{Guid.NewGuid():N}.tmp");
        try {
            File.WriteAllBytes(temporary, JsonSerializer.SerializeToUtf8Bytes(settings, CueJsonContext.Default.LocalSettings));
            if (File.Exists(path)) File.Replace(temporary, path, null);
            else File.Move(temporary, path);
        } finally {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }
}
