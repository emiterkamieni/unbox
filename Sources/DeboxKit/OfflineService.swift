import Foundation

public struct OnlineOnlyOutcome: Sendable {
    public let freedBytes: Int64
    /// Files that are still stored locally, e.g. because they have changes that were not uploaded yet.
    public let filesKeptLocally: Int
}

public final class OfflineService: @unchecked Sendable {
    public let paths: BoxPaths
    public let bridge = FileProviderBridge.shared

    public init() throws {
        DiskUsage.preventDownloadsByThisProcess()
        paths = try BoxPaths.detect()
    }

    public var canChangeOfflineState: Bool { bridge.canPerformActions }

    // MARK: - Scanning

    public func scan() async throws -> [OfflineItem] {
        let candidates: [OfflineItem]
        do {
            candidates = try BoxDatabase(paths: paths).offlineRoots().map {
                OfflineItem(relativePath: $0.relativePath, url: paths.url(forRelativePath: $0.relativePath), isFolder: !$0.isFile)
            }
        } catch {
            guard bridge.canReadItems else { throw error }
            return await scanWithFileProvider()
        }
        return await verified(candidates)
    }

    /// The database copy can lag behind by a moment, so every candidate is confirmed with macOS.
    private func verified(_ candidates: [OfflineItem]) async -> [OfflineItem] {
        let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard bridge.canReadItems else { return existing }

        return await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, item) in existing.enumerated() {
                group.addTask { [bridge] in
                    guard let info = try? await bridge.item(at: item.url) else { return (index, true) }
                    return (index, info.isMarkedOffline)
                }
            }
            var keep = Array(repeating: false, count: existing.count)
            for await (index, isOffline) in group { keep[index] = isOffline }
            return existing.enumerated().filter { keep[$0.offset] }.map(\.element)
        }
    }

    /// Fallback when Box changes its database: walks downloaded folders and asks macOS about each item.
    private func scanWithFileProvider() async -> [OfflineItem] {
        var result: [OfflineItem] = []
        var queue: [URL] = [paths.syncRoot]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        while !queue.isEmpty {
            let folder = queue.removeFirst()
            guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                guard isMaterialized(child) else { continue }
                let isDirectory = (try? child.resourceValues(forKeys: Set(keys)).isDirectory) ?? false
                if let info = try? await bridge.item(at: child), info.isMarkedOffline,
                   let relative = paths.relativePath(for: child) {
                    result.append(OfflineItem(relativePath: relative, url: child, isFolder: isDirectory))
                } else if isDirectory {
                    queue.append(child)
                }
            }
        }
        return result.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    /// Offline items are always downloaded, so dataless (cloud-only) entries can be skipped.
    private func isMaterialized(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & 0x4000_0000 == 0
    }

    // MARK: - Changing state

    /// Same as Finder's "Make Available Online Only", optionally followed by removing the local copies.
    public func makeOnlineOnly(_ item: OfflineItem, freeSpace: Bool) async throws -> OnlineOnlyOutcome {
        let before = DiskUsage.allocatedSize(of: item.url)
        let info = try await bridge.item(at: item.url)

        if info.isMarkedOffline {
            try await bridge.perform(.unmarkForOffline, on: info)
            try await waitUntil(item, isMarkedOffline: false)
        }

        guard freeSpace else {
            return OnlineOnlyOutcome(freedBytes: 0, filesKeptLocally: DiskUsage.downloadedFiles(under: item.url).count)
        }

        try await removeLocalCopies(of: item.url)
        let after = await settledSize(of: item.url)
        return OnlineOnlyOutcome(
            freedBytes: max(0, before - after),
            filesKeptLocally: DiskUsage.downloadedFiles(under: item.url).count
        )
    }

    /// Diagnostic helper used by the command line tool.
    public func makeAvailableOffline(_ url: URL) async throws {
        let info = try await bridge.item(at: url)
        try await bridge.perform(.markForOffline, on: info)
    }

    private func waitUntil(_ item: OfflineItem, isMarkedOffline expected: Bool) async throws {
        for _ in 0..<30 {
            if let info = try? await bridge.item(at: item.url), info.isMarkedOffline == expected { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw DeboxError.boxDidNotApply(item.name)
    }

    private func removeLocalCopies(of url: URL) async throws {
        // Box needs a moment to release its "keep downloaded" policy after unmarking.
        for attempt in 0..<4 {
            do {
                try bridge.evict(url)
                return
            } catch {
                if attempt < 3 { try await Task.sleep(nanoseconds: 1_500_000_000) }
            }
        }
        // A folder is refused as a whole when one of its files cannot be evicted
        // (e.g. it was not uploaded yet), so evict file by file and keep the rest.
        for file in DiskUsage.downloadedFiles(under: url) {
            try? bridge.evict(file)
        }
    }

    private func settledSize(of url: URL) async -> Int64 {
        var last = DiskUsage.allocatedSize(of: url)
        for _ in 0..<10 {
            if last == 0 { return 0 }
            try? await Task.sleep(nanoseconds: 500_000_000)
            let current = DiskUsage.allocatedSize(of: url)
            if current == last { return current }
            last = current
        }
        return last
    }
}
