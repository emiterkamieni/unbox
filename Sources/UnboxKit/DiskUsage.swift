import Darwin
import Foundation

public enum DiskUsage {
    private static let datalessFlag: UInt32 = 0x4000_0000 // SF_DATALESS

    /// Makes sure this process never downloads cloud files just by looking at them.
    /// Reading a dataless folder fails instead of fetching it from Box.
    public static func preventDownloadsByThisProcess() {
        _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    }

    /// Space that is actually used on disk by the downloaded part of `url`.
    public static func allocatedSize(of url: URL) -> Int64 {
        var total: Int64 = 0
        walk(url) { _, info in total += Int64(info.st_blocks) * 512 }
        return total
    }

    /// Regular files under `url` that currently have local content.
    public static func downloadedFiles(under url: URL) -> [URL] {
        var result: [URL] = []
        walk(url) { path, _ in result.append(URL(fileURLWithPath: path)) }
        return result
    }

    private static func walk(_ url: URL, visitFile: (String, stat) -> Void) {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return }
        visit(path: url.path, info: info, visitFile: visitFile)
    }

    private static func visit(path: String, info: stat, visitFile: (String, stat) -> Void) {
        if info.st_flags & datalessFlag != 0 { return }
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            visitFile(path, info)
        case S_IFDIR:
            guard let dir = opendir(path) else { return }
            defer { closedir(dir) }
            while let entry = readdir(dir) {
                let name = withUnsafePointer(to: entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                let child = path + "/" + name
                var childInfo = stat()
                if lstat(child, &childInfo) == 0 {
                    visit(path: child, info: childInfo, visitFile: visitFile)
                }
            }
        default:
            return
        }
    }
}
