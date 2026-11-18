import AppKit
import SwiftUI

/// Logo assets generated from docs/*.svg by scripts/make-icons.swift (the colour is in BrandColor.swift).
enum Brand {
    static let symbol: NSImage = template("MenuBarIcon", fallback: "shippingbox")
    static let logo: NSImage = template("Logo", fallback: "shippingbox")

    private static func template(_ name: String, fallback: String) -> NSImage {
        let image = Bundle.main.image(forResource: name)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: "unbox")
            ?? NSImage()
        image.isTemplate = true
        image.accessibilityDescription = "unbox"
        return image
    }
}
