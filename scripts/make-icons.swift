#!/usr/bin/env swift
// Generates the app's image assets from the vector logo in docs/:
//   Support/MenuBarIcon.pdf  – template symbol for the menu bar
//   Support/Logo.pdf         – template wordmark for the popover header
//   Support/AppIcon.icns     – white symbol on a blue rounded square
//   windows/src/Unbox/Assets – AppIcon.ico, tray icons for light/dark taskbars, Brand.xaml geometries
//   Sources/Unbox/BrandColor.swift – the brand colour, taken from the logo's fill
// Usage: swift scripts/make-icons.swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let docs = root.appendingPathComponent("docs")
let support = root.appendingPathComponent("Support")
let brand = brandColor(in: docs.appendingPathComponent("unbox_logo.svg"))
let brandLight = mix(brand, with: 0xFFFFFF, 0.18)
let brandDark = mix(brand, with: 0x000000, 0.15)

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

/// The first `fill="#RRGGBB"` of the SVG, so a new logo also brings its colour.
func brandColor(in url: URL) -> UInt32 {
    let text = try! String(contentsOf: url, encoding: .utf8)
    let regex = try! NSRegularExpression(pattern: ##"fill="#([0-9A-Fa-f]{6})""##)
    guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { fatalError("no fill colour in \(url.path)") }
    return UInt32(text[range], radix: 16)!
}

func mix(_ hex: UInt32, with other: UInt32, _ amount: Double) -> UInt32 {
    [16, 8, 0].reduce(UInt32(0)) { result, shift in
        let a = Double((hex >> UInt32(shift)) & 0xFF), b = Double((other >> UInt32(shift)) & 0xFF)
        return result | (UInt32((a + (b - a) * amount).rounded()) << UInt32(shift))
    }
}

func hexString(_ hex: UInt32) -> String { String(format: "%06X", hex) }

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
    context.setFillColor(color(brand))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(brandLight), color(brand), color(brandDark)] as CFArray,
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

func pngData(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

// MARK: - Windows

func bitmapContext(_ pixels: Int) -> CGContext {
    CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Windows style: the tile fills the canvas (no macOS shadow margin), so small sizes stay legible.
func renderWindowsAppIcon(_ symbol: SVGShape, pixels: Int) -> CGImage {
    let context = bitmapContext(pixels)
    let size = CGFloat(pixels)
    let inset = pixels <= 24 ? 0 : size * 0.04
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.22, cornerHeight: tile.width * 0.22, transform: nil)
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [color(brandLight), color(brand), color(brandDark)] as CFArray, locations: [0, 0.45, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    let height = tile.height * 0.6
    let width = height * symbol.viewBox.width / symbol.viewBox.height
    draw(symbol, in: CGRect(x: tile.midX - width / 2, y: tile.midY - height / 2, width: width, height: height),
         color: CGColor(gray: 1, alpha: 1), context: context)
    return context.makeImage()!
}

/// Notification area icon: the symbol alone, black for light taskbars or white for dark ones.
func renderTrayIcon(_ symbol: SVGShape, pixels: Int, white: Bool) -> CGImage {
    let context = bitmapContext(pixels)
    let size = CGFloat(pixels)
    let height = size * 0.875
    let width = height * symbol.viewBox.width / symbol.viewBox.height
    draw(symbol, in: CGRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height),
         color: white ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1), context: context)
    return context.makeImage()!
}

/// ICO with 32-bit DIB entries up to 64 px and PNG entries above, which every Windows API can load.
func writeICO(_ images: [CGImage], to url: URL) {
    func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
    func le32(_ value: Int) -> [UInt8] { le16(value & 0xFFFF) + le16((value >> 16) & 0xFFFF) }

    let payloads: [Data] = images.map { image in
        let size = image.width
        guard size <= 64 else { return pngData(image) }
        let context = bitmapContext(size)
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        var bytes = Data(le32(40) + le32(size) + le32(size * 2) + le16(1) + le16(32) + le32(0) + le32(0) + le32(0) + le32(0) + le32(0) + le32(0))
        for row in (0..<size).reversed() { // bottom-up, BGRA, straight alpha
            for column in 0..<size {
                let offset = (row * size + column) * 4
                let alpha = pixels[offset + 3]
                func straight(_ value: UInt8) -> UInt8 { alpha == 0 ? 0 : UInt8(min(255, Int(value) * 255 / Int(alpha))) }
                bytes.append(contentsOf: [straight(pixels[offset + 2]), straight(pixels[offset + 1]), straight(pixels[offset]), alpha])
            }
        }
        let maskRow = ((size + 31) / 32) * 4
        bytes.append(Data(count: maskRow * size)) // AND mask unused with alpha
        return bytes
    }

    var file = Data(le16(0) + le16(1) + le16(images.count))
    var offset = 6 + 16 * images.count
    for (image, payload) in zip(images, payloads) {
        let size = image.width >= 256 ? 0 : image.width
        file.append(contentsOf: [UInt8(size), UInt8(size), 0, 0] + le16(1) + le16(32) + le32(payload.count) + le32(offset))
        offset += payload.count
    }
    payloads.forEach { file.append($0) }
    try! file.write(to: url)
}

/// WPF path markup with absolute commands (SVG coordinates are y-down like WPF's).
func geometryMarkup(_ shape: SVGShape) -> String {
    func number(_ value: CGFloat) -> String { String(format: "%.2f", value).replacingOccurrences(of: ".00", with: "") }
    var parts = ["F1"]
    for path in shape.paths {
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint: parts.append("M\(number(points[0].x)),\(number(points[0].y))")
            case .addLineToPoint: parts.append("L\(number(points[0].x)),\(number(points[0].y))")
            case .addQuadCurveToPoint:
                parts.append("Q\(number(points[0].x)),\(number(points[0].y)) \(number(points[1].x)),\(number(points[1].y))")
            case .addCurveToPoint:
                parts.append("C\(number(points[0].x)),\(number(points[0].y)) \(number(points[1].x)),\(number(points[1].y)) \(number(points[2].x)),\(number(points[2].y))")
            case .closeSubpath: parts.append("Z")
            @unknown default: break
            }
        }
    }
    return parts.joined(separator: " ")
}

func writeBrandXAML(logo: SVGShape, symbol: SVGShape, to url: URL) {
    let xaml = """
    <!-- Generated by scripts/make-icons.swift from docs/*.svg – do not edit. -->
    <ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
        <SolidColorBrush x:Key="BrandBlue" Color="#\(hexString(brand))" />
        <Geometry x:Key="LogoGeometry">\(geometryMarkup(logo))</Geometry>
        <Geometry x:Key="SymbolGeometry">\(geometryMarkup(symbol))</Geometry>
    </ResourceDictionary>

    """
    try! xaml.write(to: url, atomically: true, encoding: .utf8)
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

let windowsAssets = root.appendingPathComponent("windows/src/Unbox/Assets")
try FileManager.default.createDirectory(at: windowsAssets, withIntermediateDirectories: true)
writeICO([16, 20, 24, 32, 40, 48, 64, 96, 128, 256].map { renderWindowsAppIcon(symbol, pixels: $0) },
         to: windowsAssets.appendingPathComponent("AppIcon.ico"))
for (name, white) in [("TrayLight.ico", false), ("TrayDark.ico", true)] {
    writeICO([16, 20, 24, 32, 40, 48, 64].map { renderTrayIcon(symbol, pixels: $0, white: white) },
             to: windowsAssets.appendingPathComponent(name))
}
writeBrandXAML(logo: logo, symbol: symbol, to: windowsAssets.appendingPathComponent("Brand.xaml"))

let swiftColor = """
// Generated by scripts/make-icons.swift from docs/unbox_logo.svg – do not edit.
import SwiftUI

extension Brand {
    static let blue = Color(red: \((brand >> 16) & 0xFF) / 255, green: \((brand >> 8) & 0xFF) / 255, blue: \(brand & 0xFF) / 255) // #\(hexString(brand))
}

"""
try swiftColor.write(to: root.appendingPathComponent("Sources/Unbox/BrandColor.swift"), atomically: true, encoding: .utf8)
writePNG(renderWindowsAppIcon(symbol, pixels: 256), to: FileManager.default.temporaryDirectory.appendingPathComponent("unbox-win-icon.png"))
print("Gotowe: Support/ (macOS) i windows/src/Unbox/Assets/ (Windows)")
