import AppKit
import UnboxKit

/// Invented folders and files for screenshots and for trying the interface without Box Drive:
///
///     unbox --demo [--appearance light|dark] [--snapshot <folder>] [-language en]
///
/// Demo mode never reads or changes anything in Box and does not check for updates. With
/// `--snapshot` the popover is saved as macos-list.png and macos-settings.png (with a `-dark`
/// suffix in dark mode) and the app quits. `-language` overrides the saved language for one launch.
@MainActor
enum Demo {
    static let isEnabled = CommandLine.arguments.contains("--demo")
    static let snapshotFolder = argument(after: "--snapshot").map { URL(fileURLWithPath: $0, isDirectory: true) }
    static var launchAtLogin = true

    private struct Entry {
        let path: String
        let isFolder: Bool
        let gigabytes: Double
        let onlineOnly: Bool
    }

    private static let entries = [
        Entry(path: "/Acme Corp/Marketing/Brand Guidelines", isFolder: true, gigabytes: 1.24, onlineOnly: false),
        Entry(path: "/Acme Corp/Marketing/Campaigns/Spring Campaign 2026", isFolder: true, gigabytes: 6.8, onlineOnly: true),
        Entry(path: "/Acme Corp/Legal/Master Services Agreement.pdf", isFolder: false, gigabytes: 0.0021, onlineOnly: false),
        Entry(path: "/Northwind Studio/Photography/Product Shoot – RAW", isFolder: true, gigabytes: 14.3, onlineOnly: true),
        Entry(path: "/Northwind Studio/Website Redesign", isFolder: true, gigabytes: 0.842, onlineOnly: false),
        Entry(path: "/Globex/HR/Onboarding Videos", isFolder: true, gigabytes: 3.6, onlineOnly: false),
        Entry(path: "/Invoices 2026.xlsx", isFolder: false, gigabytes: 0.000186, onlineOnly: false),
    ]

    private static var removed: Set<String> = []
    private static let root = URL(fileURLWithPath: "/Users/Shared/Box (demo)", isDirectory: true)

    static var items: [OfflineItem] {
        entries.filter { !removed.contains($0.path) }.map {
            OfflineItem(relativePath: $0.path, url: root.appendingPathComponent(String($0.path.dropFirst())), isFolder: $0.isFolder)
        }
    }

    /// Finder counts in decimal units, so the sizes look the same as in the list above.
    static var sizes: [String: Int64] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.path, Int64($0.gigabytes * 1_000_000_000)) })
    }

    static var initialSelection: Set<String> {
        Set(entries.filter(\.onlineOnly).map(\.path))
    }

    /// Pretends to make the item online-only and returns the space it would free.
    static func makeOnlineOnly(_ item: OfflineItem, freeSpace: Bool, size: Int64) async -> Int64 {
        try? await Task.sleep(nanoseconds: 700_000_000)
        removed.insert(item.id)
        return freeSpace ? size : 0
    }

    static func applyAppearance() {
        switch argument(after: "--appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    // MARK: - Snapshots

    /// Saves the popover content at 2x, drawn into a popover-shaped frame (the screen may be non-Retina,
    /// and a window capture would include whatever is behind the translucent popover). The shadow is
    /// added by scripts/screenshots.sh, the same one as for the Windows screenshots.
    static func capture(_ window: NSWindow, named name: String) {
        guard let folder = snapshotFolder, let content = window.contentView else { return }
        let appearance = window.effectiveAppearance
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let scale: CGFloat = 2
        let size = content.bounds.size
        guard let contentRep = bitmap(size: size, scale: scale) else { return }
        content.cacheDisplay(in: content.bounds, to: contentRep)

        let margin: CGFloat = 1, arrow: CGFloat = 10, radius: CGFloat = 12 // the margin keeps the hairline border
        let canvas = NSSize(width: size.width + margin * 2, height: size.height + margin * 2 + arrow)
        guard let rep = bitmap(size: canvas, scale: scale), let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let body = NSRect(x: margin, y: margin, width: size.width, height: size.height)
        let outline = popoverOutline(body, radius: radius, arrow: arrow)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            NSColor(white: dark ? 0.12 : 0.97, alpha: 1).setFill()
            outline.fill()

            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            // Over the base colour (a plain draw(in:) would copy the content's transparency).
            contentRep.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            // The content brings its own base layer; the arrow gets the same one.
            NSRect(x: 0, y: body.maxY, width: canvas.width, height: arrow + 1).clip()
            NSColor.windowBackgroundColor.withAlphaComponent(0.7).setFill()
            outline.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor(white: dark ? 1 : 0, alpha: dark ? 0.16 : 0.14).setStroke()
            outline.lineWidth = 0.5
            outline.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        let url = folder.appendingPathComponent("macos-\(name)\(dark ? "-dark" : "").png")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if (try? rep.representation(using: .png, properties: [:])?.write(to: url)) != nil {
            print(url.path)
        } else {
            FileHandle.standardError.write(Data("could not save \(url.path)\n".utf8))
        }
    }

    private static func bitmap(size: NSSize, scale: CGFloat) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = size
        return rep
    }

    /// Rounded rectangle with the popover arrow in the middle of the top edge.
    private static func popoverOutline(_ rect: NSRect, radius: CGFloat, arrow: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let (top, middle, half) = (rect.maxY, rect.midX, CGFloat(13))
        path.move(to: NSPoint(x: rect.minX + radius, y: top))
        path.line(to: NSPoint(x: middle - half, y: top))
        path.curve(to: NSPoint(x: middle, y: top + arrow),
                   controlPoint1: NSPoint(x: middle - half * 0.45, y: top), controlPoint2: NSPoint(x: middle - half * 0.3, y: top + arrow))
        path.curve(to: NSPoint(x: middle + half, y: top),
                   controlPoint1: NSPoint(x: middle + half * 0.3, y: top + arrow), controlPoint2: NSPoint(x: middle + half * 0.45, y: top))
        path.appendArc(from: NSPoint(x: rect.maxX, y: top), to: NSPoint(x: rect.maxX, y: rect.minY), radius: radius)
        path.appendArc(from: NSPoint(x: rect.maxX, y: rect.minY), to: NSPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.appendArc(from: NSPoint(x: rect.minX, y: rect.minY), to: NSPoint(x: rect.minX, y: top), radius: radius)
        path.appendArc(from: NSPoint(x: rect.minX, y: top), to: NSPoint(x: rect.maxX, y: top), radius: radius)
        path.close()
        return path
    }

    private static func argument(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
