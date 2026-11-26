import SwiftUI

/// Draws the chosen style for the live song (or, in previews only, the demo verses).
struct LyricStageView: View {
    enum Mode: Equatable {
        case lockScreen
        case desktop
        case present
        case preview(compact: Bool)
    }

    var mode: Mode
    var styleOverride: LyricStyle?
    /// Previews show demo verses when the song has no lyrics; overlays never do.
    var allowDemo = false
    var animating = true

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engine = LyricEngine.shared
    @ObservedObject private var monitor = NowPlayingMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var compact: Bool { if case .preview(let c) = mode { return c } else { return false } }
    private var isOverlay: Bool { mode == .lockScreen || mode == .desktop }
    private var isFullScreen: Bool { isOverlay || mode == .present }

    var body: some View {
        let style = styleOverride ?? settings.style
        let theme = LyricTheme.current(settings: settings, palette: monitor.palette)
        let live = engine.lyrics != nil
        let showDemo = !live && allowDemo
        let paused = !animating || (!showDemo && !monitor.isPlaying && style != .codestyle && style != .messages)

        TimelineView(.animation(minimumInterval: frameInterval, paused: paused)) { _ in
            let uptime = ProcessInfo.processInfo.systemUptime
            let frame = showDemo ? DemoLyrics.frame(at: uptime) : engine.frame(at: uptime)
            GeometryReader { geo in
                let safe = safeRect(in: geo.size)
                let shake = CameraShake.at(frame, level: settings.effectiveShake, extent: safe.size, reduceMotion: reduceMotion)
                let ctx = StyleContext(frame: frame, theme: theme, size: safe.size, now: uptime, compact: compact,
                                       title: showDemo ? "Preview" : (monitor.sample?.title ?? ""),
                                       artist: showDemo ? "Lyrik" : (monitor.sample?.artist ?? ""),
                                       artwork: showDemo ? nil : monitor.artwork, reduceMotion: reduceMotion,
                                       shake: shake)
                ZStack {
                    if isOverlay && settings.dimBackdrop && (live || showDemo) {
                        LyricBackdrop(color: theme.backdrop, strength: mode == .lockScreen ? 1 : 0.6)
                            .transition(.opacity)
                    }
                    if live || showDemo {
                        styleView(style, ctx)
                            .frame(width: safe.width, height: safe.height)
                            // Rasterise the whole style in one Metal pass instead of
                            // compositing every word layer on the CPU each frame.
                            .drawingGroup(opaque: false, colorMode: .linear)
                            // The camera reacts to every sung word (a cheap GPU transform).
                            .cameraShake(shake)
                            .position(x: safe.midX, y: safe.midY)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    if isFullScreen && settings.edgeGlow && live {
                        EdgeGlow(color: theme.accent, pulse: max(Self.pulse(frame), min(1, shake.energy)))
                            .transition(.opacity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.easeInOut(duration: 0.6), value: live)
            }
        }
        .allowsHitTesting(!isFullScreen)
    }

    /// 1 the instant a word lands, easing back to 0 over a third of a second.
    static func pulse(_ f: LyricFrame) -> Double {
        guard let wi = f.wordIndex, let w = f.current?.words[wi] else { return 0 }
        return max(0, 1 - (f.time - w.start) / 0.35)
    }

    /// The lock screen gets full smoothness; elsewhere 30 fps is plenty and half the cost.
    private var frameInterval: Double {
        switch mode {
        case .lockScreen: return 1.0 / 60
        case .desktop: return 1.0 / 30
        case .present: return 1.0 / 60
        case .preview(let compact): return compact ? 1.0 / 24 : 1.0 / 60
        }
    }

    /// Keeps words clear of the lock screen's clock (top) and login controls (bottom).
    private func safeRect(in size: CGSize) -> CGRect {
        switch mode {
        case .lockScreen:
            return CGRect(x: size.width * 0.04, y: size.height * 0.30, width: size.width * 0.92, height: size.height * 0.46)
        case .desktop:
            return CGRect(x: size.width * 0.05, y: size.height * 0.2, width: size.width * 0.9, height: size.height * 0.6)
        case .present:
            return CGRect(x: size.width * 0.05, y: size.height * 0.08, width: size.width * 0.9, height: size.height * 0.84)
        case .preview:
            return CGRect(origin: .zero, size: size)
        }
    }

    @ViewBuilder
    private func styleView(_ style: LyricStyle, _ ctx: StyleContext) -> some View {
        switch style {
        case .stack: StackStyleView(ctx: ctx)
        case .visual: VisualStyleView(ctx: ctx)
        case .fisheye: FisheyeStyleView(ctx: ctx)
        case .codestyle: CodestyleStyleView(ctx: ctx)
        case .flashbang: FlashbangStyleView(ctx: ctx)
        case .constellation: ConstellationStyleView(ctx: ctx)
        case .branches: BranchesStyleView(ctx: ctx)
        case .wall: WallStyleView(ctx: ctx)
        case .messages: MessagesStyleView(ctx: ctx)
        case .notifications: NotificationsStyleView(ctx: ctx)
        }
    }
}


/// A soft glow hugging the screen edges, tinted by the album and breathing with each word.
struct EdgeGlow: View {
    var color: Color
    var pulse: Double

    var body: some View {
        GeometryReader { g in
            let w = max(3, min(g.size.width, g.size.height) * 0.006)
            ZStack {
                // Wide, faint bloom…
                Rectangle()
                    .strokeBorder(color.opacity(0.35 + 0.25 * pulse), lineWidth: w * 3)
                    .blur(radius: w * 4)
                // …around a thin bright neon line.
                Rectangle()
                    .strokeBorder(color.opacity(0.7 + 0.3 * pulse), lineWidth: max(1, w * 0.45))
                    .blur(radius: w * 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}
