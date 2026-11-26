import AppKit
import SwiftUI

/// Colors pulled from album art: a deep background, a vivid accent, and readable text.
struct ArtworkPalette: Equatable {
    var background: NSColor
    var accent: NSColor
    var text: NSColor
    var secondary: NSColor

    static func == (a: Self, b: Self) -> Bool {
        a.background == b.background && a.accent == b.accent
    }

    static func extract(from image: NSImage) -> ArtworkPalette? {
        let side = 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .medium
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }

        // Bucket by hue (12 sectors) and keep weighted sums.
        struct Bucket { var r = 0.0, g = 0.0, b = 0.0, weight = 0.0, count = 0.0 }
        var buckets = [Bucket](repeating: Bucket(), count: 12)
        var avg = Bucket()
        for i in 0..<(side * side) {
            let r = Double(data[i * 4]) / 255, g = Double(data[i * 4 + 1]) / 255, b = Double(data[i * 4 + 2]) / 255
            let c = NSColor(deviceRed: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            avg.r += r; avg.g += g; avg.b += b; avg.count += 1
            guard s > 0.25, v > 0.25 else { continue }
            let idx = min(11, Int(h * 12))
            let w = Double(s * v)
            buckets[idx].r += r * w; buckets[idx].g += g * w; buckets[idx].b += b * w
            buckets[idx].weight += w; buckets[idx].count += 1
        }
        guard avg.count > 0 else { return nil }
        let base = NSColor(deviceRed: avg.r / avg.count, green: avg.g / avg.count, blue: avg.b / avg.count, alpha: 1)

        var accent: NSColor
        if let best = buckets.max(by: { $0.weight < $1.weight }), best.weight > 0.5 {
            accent = NSColor(deviceRed: best.r / best.weight, green: best.g / best.weight, blue: best.b / best.weight, alpha: 1)
        } else {
            accent = .white
        }
        // Lift the accent so it reads on a dark background.
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
        accent.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        if accent != .white { accent = NSColor(deviceHue: h, saturation: min(s, 0.75), brightness: max(v, 0.92), alpha: 1) }

        base.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        let background = NSColor(deviceHue: h, saturation: min(s * 1.1, 0.8), brightness: min(v, 0.28), alpha: 1)

        return ArtworkPalette(background: background, accent: accent,
                              text: .white, secondary: NSColor.white.withAlphaComponent(0.6))
    }
}

extension NSColor {
    /// "#RRGGBBAA"
    var hexRGBA: String {
        let c = usingColorSpace(.deviceRGB) ?? self
        return String(format: "#%02X%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()), Int((c.alphaComponent * 255).rounded()))
    }

    convenience init?(hexRGBA: String) {
        var s = hexRGBA.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6 { s += "FF" }
        guard s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        self.init(deviceRed: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255,
                  blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
    }
}
