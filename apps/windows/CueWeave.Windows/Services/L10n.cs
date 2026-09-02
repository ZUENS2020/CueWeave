using System.Globalization;
using System.Text.Json;

namespace CueWeave.WinUI.Services;

public static class L10n
{
    private static readonly Dictionary<string, Dictionary<string, string>> Catalog = Load();
    private static string preference = "system";
    private static string language = Resolve("system");

    public static string Language => language;
    public static IReadOnlyCollection<string> EnglishKeys => Catalog.GetValueOrDefault("en")?.Keys.ToArray() ?? [];
    public static IReadOnlyCollection<string> ChineseKeys => Catalog.GetValueOrDefault("zh")?.Keys.ToArray() ?? [];

    public static void Apply(string? value)
    {
        var next = value is "en" or "zh" or "system" ? value : "system";
        preference = next;
        language = Resolve(next);
    }

    public static string T(string key, params object[] args)
    {
        var table = Catalog.GetValueOrDefault(language) ?? Catalog.GetValueOrDefault("en");
        var fallback = Catalog.GetValueOrDefault("en");
        var value = table?.GetValueOrDefault(key) ?? fallback?.GetValueOrDefault(key) ?? key;
        for (var index = 0; index < args.Length; index++)
            value = value.Replace("{" + index + "}", args[index]?.ToString() ?? "");
        return value;
    }

    public static string WrapError(string message)
    {
        if (message.Contains("[authentication]") || message.Contains("HTTP 401") || message.Contains("HTTP 403"))
            return T("error.auth", message);
        if (message.Contains("[quota]") || message.Contains("HTTP 429"))
            return T("error.quota", message);
        if (message.Contains("timed out", StringComparison.OrdinalIgnoreCase))
            return T("error.timeout", message);
        if (message.Contains("14 MiB") || message.Contains("19 MiB"))
            return T("error.tooLarge", message);
        if (message.Contains("invalid alignment"))
            return T("error.invalidAlignment", message);
        if (message.Contains("invalid after a value", StringComparison.OrdinalIgnoreCase)
            && !message.Contains("CueWeave Core"))
            return T("error.invalidResponse", message);
        if (WinPaths.IsTooLong(message))
            return T("error.pathTooLong", message);
        return message;
    }

    public static string Resolve(string value)
    {
        if (value is "en" or "zh") return value;
        return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "zh" ? "zh" : "en";
    }

    private static Dictionary<string, Dictionary<string, string>> Load()
    {
        foreach (var path in CatalogPaths())
        {
            try
            {
                if (!File.Exists(path)) continue;
                var parsed = JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, string>>>(File.ReadAllBytes(path));
                if (parsed is not null && parsed.ContainsKey("en") && parsed.ContainsKey("zh")) return parsed;
            }
            catch { }
        }
        return new Dictionary<string, Dictionary<string, string>>();
    }

    private static IEnumerable<string> CatalogPaths()
    {
        yield return Path.Combine(AppContext.BaseDirectory, "l10n.json");
        var directory = new DirectoryInfo(Directory.GetCurrentDirectory());
        for (var depth = 0; depth < 8 && directory is not null; depth++, directory = directory.Parent)
            yield return Path.Combine(directory.FullName, "apps", "shared", "l10n.json");
    }
}
