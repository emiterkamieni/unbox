import Foundation

public enum UnboxError: LocalizedError {
    case boxNotInstalled
    case syncRootMissing(String)
    case databaseUnavailable(String)
    case unsupportedDatabase
    case fileProviderUnavailable
    case itemNotInBox(String)
    case itemNotMarkedOffline(String)
    case actionFailed(String)
    case actionTimedOut
    case boxDidNotApply(String)

    public var errorDescription: String? {
        switch self {
        case .boxNotInstalled:
            return L10n.text("Box Drive data was not found on this Mac.",
                             "Nie znaleziono danych Box Drive na tym komputerze.")
        case .syncRootMissing(let path):
            return L10n.format("The Box folder does not exist: %@", "Folder Box nie istnieje: %@", path)
        case .databaseUnavailable(let reason):
            return L10n.format("Could not read the Box Drive database: %@",
                               "Nie udało się odczytać bazy Box Drive: %@", reason)
        case .unsupportedDatabase:
            return L10n.text("This version of Box Drive uses an unsupported database format.",
                             "Ta wersja Box Drive ma nieobsługiwany format bazy danych.")
        case .fileProviderUnavailable:
            return L10n.text("This version of macOS does not allow automatic changes. In Finder, right-click the item and choose Make Available Online Only.",
                             "Ta wersja macOS nie pozwala na automatyczne odznaczanie. W Finderze kliknij element prawym przyciskiem i wybierz Make Available Online Only.")
        case .itemNotInBox(let path):
            return L10n.format("This item is not in Box: %@", "Element nie należy do Box: %@", path)
        case .itemNotMarkedOffline(let name):
            return L10n.format("“%@” is no longer available offline.", "„%@” nie jest już oznaczony jako offline.", name)
        case .actionFailed(let reason):
            return L10n.format("Box rejected the change: %@", "Box odrzucił operację: %@", reason)
        case .actionTimedOut:
            return L10n.text("Box did not respond in time.", "Box nie odpowiedział w wymaganym czasie.")
        case .boxDidNotApply(let name):
            return L10n.format("Box did not change “%@”. Try again or use Finder.",
                               "Box nie zmienił stanu „%@”. Spróbuj ponownie lub użyj Findera.", name)
        }
    }
}

public struct BoxPaths: Sendable {
    public let dataDirectory: URL
    public let syncRoot: URL

    public var database: URL { dataDirectory.appendingPathComponent("streemfs.db") }

    public static func detect() throws -> BoxPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let data = home.appendingPathComponent("Library/Application Support/Box/Box/data", isDirectory: true)
        guard FileManager.default.fileExists(atPath: data.path) else { throw UnboxError.boxNotInstalled }

        var root = home.appendingPathComponent("Library/CloudStorage/Box-Box", isDirectory: true)
        let marker = data.appendingPathComponent("shell/sync_root_folder.txt")
        if let text = try? String(contentsOf: marker, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { root = URL(fileURLWithPath: trimmed, isDirectory: true) }
        }
        guard FileManager.default.fileExists(atPath: root.path) else { throw UnboxError.syncRootMissing(root.path) }
        return BoxPaths(dataDirectory: data, syncRoot: root)
    }

    public func url(forRelativePath relativePath: String) -> URL {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(syncRoot) { $0.appendingPathComponent(String($1)) }
    }

    public func relativePath(for url: URL) -> String? {
        let rootPath = syncRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count))
    }
}
