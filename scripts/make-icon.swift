// Renders Lyrik's original app icon into an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(px)
    cg.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: 824pt tile centred on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    cg.addPath(shape)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(shape)
    cg.clip()
    let colors = [NSColor(srgbRed: 0.42, green: 0.20, blue: 0.86, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.98, green: 0.36, blue: 0.47, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 824, y: 924), options: [])

    // Soft top sheen.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    cg.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])

    // Three lyric lines; the middle one is being sung.
    func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ alpha: CGFloat) {
        let r = CGRect(x: x, y: y, width: w, height: h)
        cg.addPath(CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        cg.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        cg.fillPath()
    }
    bar(262, 632, 300, 62, 0.45)
    bar(262, 482, 500, 84, 1.0)
    bar(262, 350, 380, 62, 0.45)
    // A small glow dot marking the current word.
    cg.setShadow(offset: .zero, blur: 30, color: NSColor.white.cgColor)
    cg.addEllipse(in: CGRect(x: 790, y: 500, width: 48, height: 48))
    cg.setFillColor(NSColor.white.cgColor)
    cg.fillPath()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
