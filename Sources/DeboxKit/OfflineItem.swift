import Foundation

public struct OfflineItem: Identifiable, Hashable, Sendable {
    /// Path relative to the Box root, e.g. "/McDonald/Projekt/anim".
    public let relativePath: String
    public let url: URL
    public let isFolder: Bool

    public var id: String { relativePath }
    public var name: String { components.last ?? relativePath }

    /// Top-level Box folder (usually the client). Items placed directly in the Box root return "Box".
    public var group: String { components.count > 1 ? components[0] : "Box" }

    /// Folders between the group and the item itself.
    public var intermediatePath: [String] {
        components.count > 2 ? Array(components[1..<(components.count - 1)]) : []
    }

    private var components: [String] {
        relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    public init(relativePath: String, url: URL, isFolder: Bool) {
        self.relativePath = relativePath
        self.url = url
        self.isFolder = isFolder
    }
}
