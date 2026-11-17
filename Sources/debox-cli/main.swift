import DeboxKit
import Foundation

let usage = """
Użycie:
  debox-cli list [--sizes]           foldery i pliki oznaczone offline
  debox-cli status <ścieżka>         stan elementu według macOS i Box
  debox-cli unmark <ścieżka> [--keep-local]
                                     tylko online + zwolnienie miejsca
  debox-cli mark <ścieżka>           oznacz offline (diagnostyka)
  debox-cli evict <ścieżka>          usuń lokalną kopię (diagnostyka)
"""

func formatted(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func resolve(_ argument: String) -> URL {
    URL(fileURLWithPath: (argument as NSString).expandingTildeInPath).standardizedFileURL
}

func run() async throws -> Int32 {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        print(usage)
        return 1
    }
    arguments.removeFirst()
    let service = try OfflineService()

    switch command {
    case "list":
        let showSizes = arguments.contains("--sizes")
        let items = try await service.scan()
        var total: Int64 = 0
        for item in items {
            let kind = item.isFolder ? "folder" : "plik  "
            if showSizes {
                let size = DiskUsage.allocatedSize(of: item.url)
                total += size
                print("\(kind)  \(formatted(size).padding(toLength: 10, withPad: " ", startingAt: 0))  \(item.relativePath)")
            } else {
                print("\(kind)  \(item.relativePath)")
            }
        }
        print("Razem: \(items.count)" + (showSizes ? ", \(formatted(total))" : ""))

    case "status":
        guard let path = arguments.first else { print(usage); return 1 }
        let url = resolve(path)
        let info = try await service.bridge.item(at: url)
        print("offline:      \(info.isMarkedOffline ? "tak" : "nie")")
        print("pobrany:      \(info.isDownloaded ? "tak" : "nie")")
        print("wysłany:      \(info.isUploaded ? "tak" : "nie")")
        print("na dysku:     \(formatted(DiskUsage.allocatedSize(of: url)))")
        print("plików lok.:  \(DiskUsage.downloadedFiles(under: url).count)")

    case "unmark":
        guard let path = arguments.first else { print(usage); return 1 }
        let url = resolve(path)
        guard let relative = service.paths.relativePath(for: url) else { throw DeboxError.itemNotInBox(url.path) }
        let item = OfflineItem(relativePath: relative, url: url, isFolder: true)
        let outcome = try await service.makeOnlineOnly(item, freeSpace: !arguments.contains("--keep-local"))
        print("Tylko online: \(relative)")
        print("Zwolniono: \(formatted(outcome.freedBytes)), plików zostało lokalnie: \(outcome.filesKeptLocally)")

    case "mark":
        guard let path = arguments.first else { print(usage); return 1 }
        try await service.makeAvailableOffline(resolve(path))
        print("Oznaczono offline.")

    case "evict":
        guard let path = arguments.first else { print(usage); return 1 }
        try service.bridge.evict(resolve(path))
        print("Usunięto lokalną kopię.")

    default:
        print(usage)
        return 1
    }
    return 0
}

do {
    exit(try await run())
} catch {
    FileHandle.standardError.write(Data("Błąd: \(error.localizedDescription)\n".utf8))
    exit(2)
}
