using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Unbox.Kit;

public enum AppLanguage
{
    System, English, Polish, German, French, Spanish, Italian, Portuguese, Dutch, Swedish,
    Czech, Ukrainian, Japanese, Korean, SimplifiedChinese, TraditionalChinese,
}

public static class AppLanguages
{
    private static readonly Dictionary<AppLanguage, (string Code, string Name)> Table = new()
    {
        [AppLanguage.English] = ("en", "English"),
        [AppLanguage.Polish] = ("pl", "Polski"),
        [AppLanguage.German] = ("de", "Deutsch"),
        [AppLanguage.French] = ("fr", "Français"),
        [AppLanguage.Spanish] = ("es", "Español"),
        [AppLanguage.Italian] = ("it", "Italiano"),
        [AppLanguage.Portuguese] = ("pt", "Português"),
        [AppLanguage.Dutch] = ("nl", "Nederlands"),
        [AppLanguage.Swedish] = ("sv", "Svenska"),
        [AppLanguage.Czech] = ("cs", "Čeština"),
        [AppLanguage.Ukrainian] = ("uk", "Українська"),
        [AppLanguage.Japanese] = ("ja", "日本語"),
        [AppLanguage.Korean] = ("ko", "한국어"),
        [AppLanguage.SimplifiedChinese] = ("zh-Hans", "简体中文"),
        [AppLanguage.TraditionalChinese] = ("zh-Hant", "繁體中文"),
    };

    public static IReadOnlyList<AppLanguage> All { get; } = Enum.GetValues<AppLanguage>();

    public static string Code(this AppLanguage language) => language == AppLanguage.System ? "system" : Table[language].Code;

    public static string NativeName(this AppLanguage language) =>
        language == AppLanguage.System ? L10n.Text("System language", "Język systemu") : Table[language].Name;

    public static AppLanguage FromCode(string? code) =>
        Table.FirstOrDefault(pair => pair.Value.Code == code).Key is var found && found != default ? found : AppLanguage.System;
}

/// <summary>
/// Interface text. English and Polish are written at the call sites; the other languages come
/// from Localizations\&lt;code&gt;.json, keyed by the English text (shared with the macOS app).
/// Templates use printf placeholders (%@ for text, %ld for numbers) like the macOS catalogs.
/// </summary>
public static class L10n
{
    private static readonly object Gate = new();
    private static readonly Dictionary<AppLanguage, Dictionary<string, string>> Catalogs = new();
    private static AppLanguage effective = Resolve(CultureInfo.CurrentUICulture.Name);

    public static event Action? Changed;

    public static AppLanguage Effective { get { lock (Gate) return effective; } }

    public static CultureInfo Culture => Effective switch
    {
        AppLanguage.English => CultureInfo.GetCultureInfo("en-US"),
        var language => CultureInfo.GetCultureInfo(language.Code()),
    };

    public static AppLanguage Resolve(params string[] preferredLanguages)
    {
        foreach (var identifier in preferredLanguages)
        {
            var parts = identifier.Replace('_', '-').ToLowerInvariant().Split('-');
            if (parts[0] == "zh")
            {
                if (parts.Contains("hant")) return AppLanguage.TraditionalChinese;
                if (parts.Contains("hans")) return AppLanguage.SimplifiedChinese;
                return parts.Any(part => part is "tw" or "hk" or "mo") ? AppLanguage.TraditionalChinese : AppLanguage.SimplifiedChinese;
            }
            var match = AppLanguages.All.FirstOrDefault(language => language != AppLanguage.System && language.Code() == parts[0]);
            if (match != AppLanguage.System) return match;
        }
        return AppLanguage.English;
    }

    public static void Configure(AppLanguage language)
    {
        var resolved = language == AppLanguage.System ? Resolve(CultureInfo.InstalledUICulture.Name, CultureInfo.CurrentUICulture.Name) : language;
        lock (Gate) effective = resolved;
        Changed?.Invoke();
    }

    public static string Text(string english, string polish) => Translated(english, polish, Effective);

    public static string Format(string english, string polish, params object[] args) =>
        Printf(Translated(english, polish, Effective), args);

    /// <summary>Catalog keys are @key.one/few/many/other; the template receives the count as %ld.</summary>
    public static string Plural(string key, long count, (string One, string Other) english, (string One, string Few, string Many) polish)
    {
        var language = Effective;
        var category = PluralCategory(count, language);
        var fallback = language == AppLanguage.Polish
            ? category switch { "one" => polish.One, "few" => polish.Few, _ => polish.Many }
            : category == "one" ? english.One : english.Other;
        var table = Catalog(language);
        var template = table.GetValueOrDefault($"@{key}.{category}") ?? table.GetValueOrDefault($"@{key}.other") ?? fallback;
        return Printf(template, count);
    }

    public static string PluralCategory(long count, AppLanguage language)
    {
        long last = count % 10, lastTwo = count % 100;
        bool few = last is >= 2 and <= 4 && lastTwo is < 12 or > 14;
        return language switch
        {
            AppLanguage.Polish => count == 1 ? "one" : few ? "few" : "many",
            AppLanguage.Ukrainian => last == 1 && lastTwo != 11 ? "one" : few ? "few" : "many",
            AppLanguage.Czech => count == 1 ? "one" : count is >= 2 and <= 4 ? "few" : "other",
            AppLanguage.Japanese or AppLanguage.Korean or AppLanguage.SimplifiedChinese or AppLanguage.TraditionalChinese => "other",
            AppLanguage.French or AppLanguage.Portuguese => count is 0 or 1 ? "one" : "other",
            _ => count == 1 ? "one" : "other",
        };
    }

    /// <summary>
    /// Sizes like File Explorer shows them (binary units, three significant digits), but with the
    /// number format of the interface language rather than the system's, as on macOS.
    /// </summary>
    public static string Bytes(long bytes)
    {
        string[] units = Effective switch
        {
            AppLanguage.French => ["o", "Ko", "Mo", "Go", "To"],
            AppLanguage.Ukrainian => ["Б", "КБ", "МБ", "ГБ", "ТБ"],
            _ => ["B", "KB", "MB", "GB", "TB"],
        };
        double value = Math.Max(0, bytes);
        if (value < 1024) return $"{value.ToString("0", Culture)} {units[0]}";
        int unit = 1;
        value /= 1024;
        while (value >= 999.5 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }
        string format = value < 9.995 ? "0.00" : value < 99.95 ? "0.0" : "0";
        return $"{value.ToString(format, Culture)} {units[unit]}";
    }

    /// <summary>Replaces %@, %ld and %d in order; numbers use the interface culture.</summary>
    public static string Printf(string template, params object[] args)
    {
        var result = new StringBuilder(template.Length + 16);
        int next = 0;
        for (int i = 0; i < template.Length; i++)
        {
            if (template[i] != '%' || i + 1 >= template.Length) { result.Append(template[i]); continue; }
            if (template[i + 1] == '%') { result.Append('%'); i++; continue; }
            int length = template[i + 1] == '@' || template[i + 1] == 'd' ? 1
                : template.AsSpan(i + 1).StartsWith("ld") ? 2 : 0;
            if (length == 0 || next >= args.Length) { result.Append(template[i]); continue; }
            var value = args[next++];
            result.Append(value is IFormattable formattable ? formattable.ToString(null, Culture) : value?.ToString());
            i += length;
        }
        return result.ToString();
    }

    private static string Translated(string english, string polish, AppLanguage language) =>
        Catalog(language).GetValueOrDefault(english) ?? (language == AppLanguage.Polish ? polish : english);

    private static Dictionary<string, string> Catalog(AppLanguage language)
    {
        if (language is AppLanguage.English or AppLanguage.Polish) return [];
        lock (Gate)
        {
            if (Catalogs.TryGetValue(language, out var cached)) return cached;
            var path = Path.Combine(AppContext.BaseDirectory, "Localizations", language.Code() + ".json");
            Dictionary<string, string> table = [];
            try
            {
                if (File.Exists(path)) table = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path)) ?? [];
            }
            catch (JsonException) { }
            Catalogs[language] = table;
            return table;
        }
    }
}
