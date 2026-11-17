import Foundation

public enum DeboxError: LocalizedError {
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
            return "Nie znaleziono danych Box Drive na tym komputerze."
        case .syncRootMissing(let path):
            return "Folder Box nie istnieje: \(path)"
        case .databaseUnavailable(let reason):
            return "Nie udało się odczytać bazy Box Drive: \(reason)"
        case .unsupportedDatabase:
            return "Ta wersja Box Drive ma nieobsługiwany format bazy danych."
        case .fileProviderUnavailable:
            return "Ta wersja macOS nie pozwala na automatyczne odznaczanie. Użyj Findera: prawy przycisk → Make Available Online Only."
        case .itemNotInBox(let path):
            return "Element nie należy do Box: \(path)"
        case .itemNotMarkedOffline(let name):
            return "„\(name)” nie jest już oznaczony jako offline."
        case .actionFailed(let reason):
            return "Box odrzucił operację: \(reason)"
        case .actionTimedOut:
            return "Box nie odpowiedział w wymaganym czasie."
        case .boxDidNotApply(let name):
            return "Box nie zmienił stanu „\(name)”. Spróbuj ponownie lub użyj Findera."
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
        guard FileManager.default.fileExists(atPath: data.path) else { throw DeboxError.boxNotInstalled }

        var root = home.appendingPathComponent("Library/CloudStorage/Box-Box", isDirectory: true)
        let marker = data.appendingPathComponent("shell/sync_root_folder.txt")
        if let text = try? String(contentsOf: marker, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { root = URL(fileURLWithPath: trimmed, isDirectory: true) }
        }
        guard FileManager.default.fileExists(atPath: root.path) else { throw DeboxError.syncRootMissing(root.path) }
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
