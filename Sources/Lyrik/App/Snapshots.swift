import AppKit
import SwiftUI

/// Diagnostics: `Lyrik --snapshot <dir>` renders the window, the menu bar panel and
/// every style into PNGs from inside the app (no screen-recording permission needed).
@MainActor
enum Snapshots {
    static func run(into dir: URL, gallery: NSWindow?) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let view = gallery?.contentView { save(view, to: dir.appendingPathComponent("window.png")) }

        for size in [CGSize(width: 960, height: 620), CGSize(width: 1180, height: 740), CGSize(width: 1500, height: 900)] {
            let host = NSHostingView(rootView: GalleryView().frame(width: size.width, height: size.height))
            host.frame = NSRect(origin: .zero, size: size)
            save(host, offscreen: true, to: dir.appendingPathComponent("window-\(Int(size.width)).png"))
        }

        let present = NSHostingView(rootView: PresentView().frame(width: 1280, height: 720))
        present.frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        save(present, offscreen: true, to: dir.appendingPathComponent("present.png"))

        let look = NSHostingView(rootView: ScrollView { LookPanel().padding(12) }.frame(width: 340, height: 760)
            .background(Color(white: 0.085)).environment(\.colorScheme, .dark))
        look.frame = NSRect(x: 0, y: 0, width: 340, height: 760)
        save(look, offscreen: true, to: dir.appendingPathComponent("look.png"))

        let popover = NSHostingView(rootView: MenuBarPopover(openWindow: {}, quit: {}))
        popover.frame = NSRect(origin: .zero, size: popover.fittingSize)
        save(popover, offscreen: true, to: dir.appendingPathComponent("popover.png"))

        for style in LyricStyle.allCases {
            let stage = ZStack {
                LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.16), .black], startPoint: .top, endPoint: .bottom)
                LyricStageView(mode: .preview(compact: false), styleOverride: style, allowDemo: true).padding(24)
            }
            let host = NSHostingView(rootView: stage.frame(width: 960, height: 540).environment(\.colorScheme, .dark))
            host.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
            save(host, offscreen: true, to: dir.appendingPathComponent("style-\(style.rawValue).png"))
        }
        // A time sequence of Constellation, to check the camera path.
        let theme = LyricTheme.current(settings: AppSettings.shared, palette: nil)
        var trace: [String] = []
        for (k, t) in [1.0, 2.2, 3.4, 4.25, 4.7, 6.0, 7.95, 9.5].enumerated() {
            let frame = LyricFrame.make(lines: DemoLyrics.lines, time: t)
            let shake = CameraShake.at(frame, level: AppSettings.shared.effectiveShake, extent: CGSize(width: 864, height: 454), reduceMotion: false)
            trace.append(String(format: "t=%.2f dx=%.1f dy=%.1f rot=%.2f° energy=%.2f", t, shake.offset.width, shake.offset.height, shake.rotation, shake.energy))
            let ctx = StyleContext(frame: frame, theme: theme, size: CGSize(width: 864, height: 454), now: t, compact: false,
                                   title: "", artist: "", artwork: nil, reduceMotion: false, shake: shake)
            let view = ZStack {
                Color.black
                ConstellationStyleView(ctx: ctx).frame(width: 864, height: 454).cameraShake(shake)
                EdgeGlow(color: Color(red: 0.9, green: 0.1, blue: 0.12), pulse: LyricStageView.pulse(frame))
            }
            .frame(width: 960, height: 540)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
            save(host, offscreen: true, to: dir.appendingPathComponent("constellation-\(k).png"))
        }
        // Shake amplitude over a stretch of song, sampled every 50 ms.
        for i in 0..<60 {
            let t = 3.9 + Double(i) * 0.05
            let s = CameraShake.at(LyricFrame.make(lines: DemoLyrics.lines, time: t), level: AppSettings.shared.effectiveShake,
                                   extent: CGSize(width: 1440, height: 900), reduceMotion: false)
            trace.append(String(format: "fs t=%.2f dx=%5.1f dy=%5.1f rot=%5.2f energy=%.2f", t, s.offset.width, s.offset.height, s.rotation, s.energy))
        }
        try? trace.joined(separator: "\n").write(to: dir.appendingPathComponent("shake.txt"), atomically: true, encoding: .utf8)
        Log.write("snapshots written to \(dir.path)")
    }

    static func save(_ view: NSView, offscreen: Bool = false, to url: URL) {
        var window: NSWindow?
        if offscreen {
            let w = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = view
            w.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            w.orderFrontRegardless()
            window = w
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
        window?.orderOut(nil)
    }
}
