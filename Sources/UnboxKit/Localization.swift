import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case polish = "pl"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case swedish = "sv"
    case czech = "cs"
    case ukrainian = "uk"
    case japanese = "ja"
    case korean = "ko"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    public var id: String { rawValue }

    public var nativeName: String {
        switch self {
        case .system: return L10n.text("System language", "Język systemu")
        case .english: return "English"
        case .polish: return "Polski"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .dutch: return "Nederlands"
        case .swedish: return "Svenska"
        case .czech: return "Čeština"
        case .ukrainian: return "Українська"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }
}

/// Interface text. English and Polish live at the call sites; the other languages come from
/// `Resources/Localizations/<code>.json`, keyed by the English text.
public enum L10n {
    private final class Selection: @unchecked Sendable {
        let lock = NSLock()
        var effective = L10n.resolve(preferredLanguages: Locale.preferredLanguages)
        var catalogs: [AppLanguage: [String: String]] = [:]
    }
    private static let selection = Selection()

    public static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
            guard let base = parts.first else { continue }
            if base == "zh" {
                if parts.contains("hant") { return .traditionalChinese }
                if parts.contains("hans") { return .simplifiedChinese }
                return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? .traditionalChinese : .simplifiedChinese
            }
            if let language = AppLanguage(rawValue: String(base)), language != .system { return language }
        }
        return .english
    }

    public static func configure(_ language: AppLanguage) {
        let effective = language == .system ? resolve(preferredLanguages: systemPreferredLanguages) : language
        selection.lock.lock()
        selection.effective = effective
        selection.lock.unlock()
    }

    /// The system-wide language list, ignoring an app-level `AppleLanguages` override.
    private static var systemPreferredLanguages: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
    }

    public static var effectiveLanguage: AppLanguage {
        selection.lock.lock(); defer { selection.lock.unlock() }
        return selection.effective
    }

    public static var locale: Locale { locale(for: effectiveLanguage) }

    private static func locale(for language: AppLanguage) -> Locale {
        Locale(identifier: language == .english ? "en_US" : language.rawValue)
    }

    public static func text(_ english: String, _ polish: String) -> String {
        translated(english, polish, language: effectiveLanguage)
    }

    public static func format(_ english: String, _ polish: String, _ args: CVarArg...) -> String {
        let language = effectiveLanguage
        return String(format: translated(english, polish, language: language), locale: locale(for: language), arguments: args)
    }

    /// Catalog keys are `@<key>.<one|few|many|other>`; the template receives `count` as `%ld`.
    public static func plural(_ key: String, count: Int, english: (one: String, other: String),
                              polish: (one: String, few: String, many: String)) -> String {
        let language = effectiveLanguage
        let category = pluralCategory(count, language: language)
        let fallback: String
        switch language {
        case .polish:
            fallback = category == "one" ? polish.one : (category == "few" ? polish.few : polish.many)
        default:
            fallback = category == "one" ? english.one : english.other
        }
        let table = catalog(for: language)
        let template = table["@\(key).\(category)"] ?? table["@\(key).other"] ?? fallback
        return String(format: template, locale: locale(for: language), count)
    }

    public static func pluralCategory(_ count: Int, language: AppLanguage) -> String {
        let last = count % 10, lastTwo = count % 100
        switch language {
        case .polish:
            if count == 1 { return "one" }
            return (2...4).contains(last) && !(12...14).contains(lastTwo) ? "few" : "many"
        case .ukrainian:
            if last == 1 && lastTwo != 11 { return "one" }
            return (2...4).contains(last) && !(12...14).contains(lastTwo) ? "few" : "many"
        case .czech:
            return count == 1 ? "one" : ((2...4).contains(count) ? "few" : "other")
        case .japanese, .korean, .simplifiedChinese, .traditionalChinese:
            return "other"
        case .french, .portuguese:
            return (0...1).contains(count) ? "one" : "other"
        default:
            return count == 1 ? "one" : "other"
        }
    }

    private static func translated(_ english: String, _ polish: String, language: AppLanguage) -> String {
        if let value = catalog(for: language)[english] { return value }
        return language == .polish ? polish : english
    }

    private static func catalog(for language: AppLanguage) -> [String: String] {
        guard language != .english, language != .polish else { return [:] }
        selection.lock.lock(); defer { selection.lock.unlock() }
        if let cached = selection.catalogs[language] { return cached }
        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL { directories.append(resources.appendingPathComponent("Localizations")) }
        // The command line tool runs without an app bundle.
        if Bundle.main.bundleURL.pathExtension != "app" {
            directories.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources/Localizations"))
        }
        let table = directories.lazy.compactMap { directory -> [String: String]? in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(language.rawValue + ".json")) else { return nil }
            return try? JSONDecoder().decode([String: String].self, from: data)
        }.first ?? [:]
        selection.catalogs[language] = table
        return table
    }
}
