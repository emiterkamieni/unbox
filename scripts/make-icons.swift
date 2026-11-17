#!/usr/bin/env swift
// Generates the app's image assets from the vector logo in docs/:
//   Support/MenuBarIcon.pdf  – template symbol for the menu bar
//   Support/Logo.pdf         – template wordmark for the popover header
//   Support/AppIcon.icns     – white symbol on a blue rounded square
// Usage: swift scripts/make-icons.swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let docs = root.appendingPathComponent("docs")
let support = root.appendingPathComponent("Support")

// MARK: - Minimal SVG path parser (M, L, H, V, C, S, Z – absolute and relative)

struct SVGShape {
    let paths: [CGPath]
    let viewBox: CGRect
}

func loadSVG(_ url: URL) throws -> SVGShape {
    let text = try String(contentsOf: url, encoding: .utf8)
    let viewBoxMatch = try NSRegularExpression(pattern: #"viewBox="([^"]+)""#)
        .firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    guard let viewBoxMatch, let range = Range(viewBoxMatch.range(at: 1), in: text) else { fatalError("no viewBox in \(url.path)") }
    let box = text[range].split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
    let pathRegex = try NSRegularExpression(pattern: #"\sd="([^"]+)""#)
    let paths = pathRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match -> CGPath in
        parsePath(String(text[Range(match.range(at: 1), in: text)!]))
    }
    return SVGShape(paths: paths, viewBox: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]))
}

func parsePath(_ data: String) -> CGPath {
    let tokenRegex = try! NSRegularExpression(pattern: #"[A-Za-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#)
    let tokens = tokenRegex.matches(in: data, range: NSRange(data.startIndex..., in: data)).map {
        String(data[Range($0.range, in: data)!])
    }
    let path = CGMutablePath()
    var index = 0
    var command: Character = "M"
    var current = CGPoint.zero
    var start = CGPoint.zero
    var lastControl: CGPoint?

    func number() -> CGFloat {
        defer { index += 1 }
        return CGFloat(Double(tokens[index])!)
    }

    while index < tokens.count {
        if let letter = tokens[index].first, letter.isLetter {
            command = letter
            index += 1
        }
        let relative = command.isLowercase
        let base = relative ? current : .zero
        switch command.uppercased() {
        case "M":
            current = CGPoint(x: base.x + number(), y: base.y + number())
            start = current
            path.move(to: current)
            command = relative ? "l" : "L" // further pairs are implicit line-tos
            lastControl = nil
        case "L":
            current = CGPoint(x: base.x + number(), y: base.y + number())
            path.addLine(to: current)
            lastControl = nil
        case "H":
            current = CGPoint(x: (relative ? current.x : 0) + number(), y: current.y)
            path.addLine(to: current)
            lastControl = nil
        case "V":
            current = CGPoint(x: current.x, y: (relative ? current.y : 0) + number())
            path.addLine(to: current)
            lastControl = nil
        case "C":
            let c1 = CGPoint(x: base.x + number(), y: base.y + number())
            let c2 = CGPoint(x: base.x + number(), y: base.y + number())
            let end = CGPoint(x: base.x + number(), y: base.y + number())
            path.addCurve(to: end, control1: c1, control2: c2)
            lastControl = c2
            current = end
        case "S":
            let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
            let c2 = CGPoint(x: base.x + number(), y: base.y + number())
            let end = CGPoint(x: base.x + number(), y: base.y + number())
            path.addCurve(to: end, control1: c1, control2: c2)
            lastControl = c2
            current = end
        case "Z":
            path.closeSubpath()
            current = start
            lastControl = nil
        default:
            fatalError("Unsupported SVG path command \(command)")
        }
    }
    return path
}

/// Draws the shape so that its viewBox fills `rect` (SVG is y-down, Core Graphics is y-up).
func draw(_ shape: SVGShape, in rect: CGRect, color: CGColor, context: CGContext) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: rect.width / shape.viewBox.width, y: -rect.height / shape.viewBox.height)
    context.translateBy(x: -shape.viewBox.minX, y: -shape.viewBox.minY)
    context.setFillColor(color)
    for path in shape.paths {
        context.addPath(path)
        context.fillPath()
    }
    context.restoreGState()
}

// MARK: - Outputs

func writeTemplatePDF(_ shape: SVGShape, height: CGFloat, to url: URL) {
    var box = CGRect(x: 0, y: 0, width: height * shape.viewBox.width / shape.viewBox.height, height: height)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    draw(shape, in: box, color: CGColor(gray: 0, alpha: 1), context: context)
    context.endPDFPage()
    context.closePDF()
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// macOS icon grid: 1024 canvas, 824 rounded square with a soft shadow underneath.
func renderAppIcon(_ symbol: SVGShape, pixels: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale,
                      color: CGColor(gray: 0, alpha: 0.28))
    context.addPath(shape)
    context.setFillColor(color(0x0179FD))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x2E94FF), color(0x0179FD), color(0x0062D6)] as CFArray,
                              locations: [0, 0.45, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
    context.restoreGState()

    let height: CGFloat = 520
    let symbolScale = height / symbol.viewBox.height
    let width = symbol.viewBox.width * symbolScale
    // Centre horizontally on the "u" (the lowest sub-shape), so the lid can overhang to the left.
    let bowl = symbol.paths.max { $0.boundingBoxOfPath.maxY < $1.boundingBoxOfPath.maxY }!.boundingBoxOfPath
    let bowlCentre = (bowl.midX - symbol.viewBox.minX) * symbolScale
    let symbolRect = CGRect(x: 512 - bowlCentre, y: 512 - height / 2, width: width, height: height)
    draw(symbol, in: symbolRect, color: CGColor(gray: 1, alpha: 1), context: context)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let symbol = try loadSVG(docs.appendingPathComponent("unbox_symbol.svg"))
let logo = try loadSVG(docs.appendingPathComponent("unbox_logo.svg"))

writeTemplatePDF(symbol, height: 16, to: support.appendingPathComponent("MenuBarIcon.pdf"))
writeTemplatePDF(logo, height: 16, to: support.appendingPathComponent("Logo.pdf"))

// Every size macOS uses (16–1024 px), named as iconutil expects.
let iconset = support.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    writePNG(renderAppIcon(symbol, pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(renderAppIcon(symbol, pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", support.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print("Gotowe: Support/MenuBarIcon.pdf, Support/Logo.pdf, Support/AppIcon.iconset, Support/AppIcon.icns")
