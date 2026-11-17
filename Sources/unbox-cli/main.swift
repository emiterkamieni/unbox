import Foundation
import UnboxKit

let usage = """
Usage:
  unbox-cli list [--sizes]           folders and files marked available offline
  unbox-cli status <path>            state of an item according to macOS and Box
  unbox-cli unmark <path> [--keep-local]
                                     make online-only and free the disk space
  unbox-cli mark <path>              make available offline (diagnostics)
  unbox-cli evict <path>             remove the local copy (diagnostics)
"""

func formatted(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func resolve(_ argument: String) -> URL {
    URL(fileURLWithPath: (argument as NSString).expandingTildeInPath).standardizedFileURL
}

func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

func run() async throws -> Int32 {
    L10n.configure(.english)
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
            let kind = item.isFolder ? "folder" : "file  "
            if showSizes {
                let size = DiskUsage.allocatedSize(of: item.url)
                total += size
                print("\(kind)  \(formatted(size).padding(toLength: 10, withPad: " ", startingAt: 0))  \(item.relativePath)")
            } else {
                print("\(kind)  \(item.relativePath)")
            }
        }
        print("Total: \(items.count)" + (showSizes ? ", \(formatted(total))" : ""))

    case "status":
        guard let path = arguments.first else { print(usage); return 1 }
        let url = resolve(path)
        let info = try await service.bridge.item(at: url)
        print("offline:      \(yesNo(info.isMarkedOffline))")
        print("downloaded:   \(yesNo(info.isDownloaded))")
        print("uploaded:     \(yesNo(info.isUploaded))")
        print("on disk:      \(formatted(DiskUsage.allocatedSize(of: url)))")
        print("local files:  \(DiskUsage.downloadedFiles(under: url).count)")

    case "unmark":
        guard let path = arguments.first else { print(usage); return 1 }
        let url = resolve(path)
        guard let relative = service.paths.relativePath(for: url) else { throw UnboxError.itemNotInBox(url.path) }
        let item = OfflineItem(relativePath: relative, url: url, isFolder: true)
        let outcome = try await service.makeOnlineOnly(item, freeSpace: !arguments.contains("--keep-local"))
        print("Online-only: \(relative)")
        print("Freed: \(formatted(outcome.freedBytes)), files still on disk: \(outcome.filesKeptLocally)")

    case "mark":
        guard let path = arguments.first else { print(usage); return 1 }
        try await service.makeAvailableOffline(resolve(path))
        print("Marked available offline.")

    case "evict":
        guard let path = arguments.first else { print(usage); return 1 }
        try service.bridge.evict(resolve(path))
        print("Local copy removed.")

    default:
        print(usage)
        return 1
    }
    return 0
}

do {
    exit(try await run())
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(2)
}
