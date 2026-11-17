import Foundation
import SQLite3

/// Reads Box Drive's own "mark for offline" flags.
///
/// Box keeps `streemfs.db` open in exclusive WAL mode, so it cannot be read in place.
/// We copy the database together with its WAL into a private temp folder and read the copy.
/// The original files are never opened for writing.
public struct BoxDatabase: Sendable {
    public let paths: BoxPaths

    public init(paths: BoxPaths) {
        self.paths = paths
    }

    public struct Root: Sendable {
        public let relativePath: String
        public let isFile: Bool
    }

    public func offlineRoots() throws -> [Root] {
        let snapshot = try makeSnapshot()
        defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(snapshot.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open"
            sqlite3_close(db)
            throw DeboxError.databaseUnavailable(message)
        }
        defer { sqlite3_close(db) }

        guard try columns(of: "fsnodes", in: db).isSuperset(of: ["inodeId", "parentInodeId", "name", "isFile", "markForOffline"]) else {
            throw DeboxError.unsupportedDatabase
        }

        let sql = """
        WITH RECURSIVE tree(inodeId, path, isFile, mfo, parentMfo) AS (
            SELECT inodeId, '', isFile, IFNULL(markForOffline, 0), 0 FROM fsnodes
             WHERE name = '' AND parentInodeId NOT IN (SELECT inodeId FROM fsnodes)
            UNION ALL
            SELECT f.inodeId, tree.path || '/' || f.name, f.isFile, IFNULL(f.markForOffline, 0), tree.mfo
              FROM fsnodes f JOIN tree ON f.parentInodeId = tree.inodeId
        )
        SELECT path, isFile FROM tree
         WHERE mfo = 1 AND parentMfo = 0 AND path != ''
         ORDER BY path COLLATE NOCASE;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DeboxError.databaseUnavailable(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var roots: [Root] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw DeboxError.databaseUnavailable(String(cString: sqlite3_errmsg(db))) }
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            roots.append(Root(relativePath: String(cString: text), isFile: sqlite3_column_int(statement, 1) != 0))
        }
        return roots
    }

    private func columns(of table: String, in db: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            throw DeboxError.databaseUnavailable(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 1) { names.insert(String(cString: text)) }
        }
        return names
    }

    /// Copies the database and WAL; retries when Box checkpoints the WAL in the middle of the copy.
    private func makeSnapshot() throws -> URL {
        let fm = FileManager.default
        let source = paths.database
        let wal = URL(fileURLWithPath: source.path + "-wal")
        guard fm.fileExists(atPath: source.path) else { throw DeboxError.databaseUnavailable("brak pliku streemfs.db") }

        let folder = fm.temporaryDirectory.appendingPathComponent("debox-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("streemfs.db")
        let targetWal = URL(fileURLWithPath: target.path + "-wal")

        for _ in 0..<5 {
            let before = signature(of: source)
            try? fm.removeItem(at: target)
            try? fm.removeItem(at: targetWal)
            do {
                try fm.copyItem(at: source, to: target)
                if fm.fileExists(atPath: wal.path) { try fm.copyItem(at: wal, to: targetWal) }
            } catch {
                continue
            }
            if signature(of: source) == before { return target }
            Thread.sleep(forTimeInterval: 0.2)
        }
        try? fm.removeItem(at: folder)
        throw DeboxError.databaseUnavailable("baza zmieniała się podczas kopiowania")
    }

    private func signature(of url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
        return "\(date)-\(size)"
    }
}
