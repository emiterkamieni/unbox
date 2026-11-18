// Adds a soft popover-like shadow and a 40 pt margin to 2x screenshots with transparency, in place.
// Used by scripts/screenshots.sh for both the macOS and the Windows images, so they match side by side.
// Files whose name ends in -dark.png get a stronger shadow, as on a dark background.
import AppKit

let scale: CGFloat = 2
let margin: CGFloat = 40

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url), let source = NSBitmapImageRep(data: data) else {
        FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
        exit(1)
    }
    let size = NSSize(width: CGFloat(source.pixelsWide) / scale, height: CGFloat(source.pixelsHigh) / scale)
    let canvas = NSSize(width: size.width + margin * 2, height: size.height + margin * 2)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    rep.size = canvas

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.shadowColor = NSColor.black.withAlphaComponent(url.lastPathComponent.hasSuffix("-dark.png") ? 0.55 : 0.22)
    shadow.set()
    source.draw(in: NSRect(origin: NSPoint(x: margin, y: margin), size: size), from: .zero, operation: .sourceOver,
                fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else {
        FileHandle.standardError.write(Data("cannot write \(path)\n".utf8))
        exit(1)
    }
    print(path)
}
