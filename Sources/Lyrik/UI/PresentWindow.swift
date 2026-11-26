import AppKit
import SwiftUI

/// A normal, shareable window that shows the lyrics full-bleed: for screen sharing in a call,
/// an external display, a projector or AirPlay. Unlike the lock-screen overlay it is an
/// ordinary window, so Zoom, Meet, FaceTime and QuickTime can capture it.
@MainActor
final class PresentWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PresentWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Lyrik — Lyrics"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.sharingType = .readOnly                 // capturable by screen-sharing apps
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 480, height: 270)
        window.contentViewController = NSHostingController(rootView: PresentView())
        window.setContentSize(NSSize(width: 1280, height: 720))
        window.center()
        window.setFrameAutosaveName("LyrikPresent")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Opens the presenter, optionally moving it to `screen` and going full screen there.
    func present(on screen: NSScreen? = nil, fullScreen: Bool = false) {
        guard let window else { return }
        if let screen {
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            let vf = screen.visibleFrame
            let size = NSSize(width: min(1280, vf.width * 0.8), height: min(720, vf.height * 0.8))
            window.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Log.write("present: opened on \(window.screen?.localizedName ?? "?")\(fullScreen ? ", full screen" : "")")
        if fullScreen && !window.styleMask.contains(.fullScreen) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { window.toggleFullScreen(nil) }
        }
    }

    func toggleFullScreen() { window?.toggleFullScreen(nil) }

    func move(to screen: NSScreen) { present(on: screen, fullScreen: window?.styleMask.contains(.fullScreen) ?? false) }

    func windowWillClose(_ notification: Notification) {
        NSCursor.unhide()
        Log.write("present: closed")
    }
}

struct PresentView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var monitor = NowPlayingMonitor.shared
    @ObservedObject var engine = LyricEngine.shared
    @State private var chromeVisible = true
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LyricStageView(mode: .present)
                .ignoresSafeArea()

            if engine.lyrics == nil {
                emptyState.transition(.opacity)
            }

            if settings.presentShowsCard, monitor.sample != nil {
                VStack {
                    Spacer()
                    HStack {
                        AlbumCard().padding(28)
                        Spacer()
                    }
                }
                .transition(.opacity)
            }

            // Credit, always in the bottom right corner (and so in any screen share).
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("Made By: Abhimanyu .")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.35)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                }
            }
            .padding(22)
            .allowsHitTesting(false)

            VStack {
                toolbar
                    .padding(.top, 34)
                    .opacity(chromeVisible ? 1 : 0)
                    .offset(y: chromeVisible ? 0 : -12)
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: chromeVisible)
        .animation(.easeInOut(duration: 0.5), value: engine.lyrics != nil)
        .animation(.easeInOut(duration: 0.4), value: settings.presentShowsCard)
        .environment(\.colorScheme, .dark)
        .onContinuousHover { phase in
            if case .active = phase { revealChrome() }
        }
        .onAppear { revealChrome(); focused = true }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(action: handleKey)
    }

    // MARK: Pieces

    private var emptyState: some View {
        VStack(spacing: 14) {
            if let s = monitor.sample {
                ArtworkView(image: monitor.artwork, size: 180, corner: 18)
                Text(s.title).font(.system(size: 34, weight: .bold)).multilineTextAlignment(.center)
                Text(s.artist).font(.system(size: 20, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                Text(engine.status.headline).font(.system(size: 14)).foregroundStyle(.white.opacity(0.4)).padding(.top, 6)
            } else {
                Image(systemName: "music.note").font(.system(size: 44)).foregroundStyle(.white.opacity(0.3))
                Text("Play a song in Spotify or Apple Music").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(40)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(LyricStyle.allCases) { s in
                    Button { settings.style = s } label: { Label(s.name, systemImage: s.symbol) }
                }
            } label: {
                Label(settings.style.name, systemImage: settings.style.symbol)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 16)
            TransportControls(size: 12)
            Divider().frame(height: 16)
            LyricTimingControl()
            Divider().frame(height: 16)

            ShakeControl(accent: LyrikAccent.current(monitor), showsTitle: false)

            Toggle(isOn: $settings.presentShowsCard) { Image(systemName: "rectangle.inset.bottomleading.filled") }
                .toggleStyle(.button).help("Album card")
            Toggle(isOn: $settings.edgeGlow) { Image(systemName: "rectangle.dashed") }
                .toggleStyle(.button).help("Edge glow")

            if NSScreen.screens.count > 1 {
                Menu {
                    ForEach(NSScreen.screens, id: \.localizedName) { screen in
                        Button(screen.localizedName) { PresentWindowController.shared.move(to: screen) }
                    }
                } label: { Image(systemName: "display.2") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Move to display")
            }
            Button { PresentWindowController.shared.toggleFullScreen() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .help("Full screen (F)")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
    }

    // MARK: Behaviour

    /// Toolbar and cursor show on movement and fade away after a moment.
    private func revealChrome() {
        chromeVisible = true
        NSCursor.unhide()
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            chromeVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .space: monitor.playPause()
        case .leftArrow: monitor.previous()
        case .rightArrow: monitor.next()
        case .escape:
            if let w = PresentWindowController.shared.window, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
            else { PresentWindowController.shared.close() }
        default:
            switch press.characters.lowercased() {
            case "f": PresentWindowController.shared.toggleFullScreen()
            case "[": engine.shift(by: 0.5)
            case "]": engine.shift(by: -0.5)
            case "c": settings.presentShowsCard.toggle()
            case "g": settings.edgeGlow.toggle()
            case "k":
                settings.shakeEnabled.toggle()
            case "s":
                let all = LyricStyle.allCases
                let i = all.firstIndex(of: settings.style) ?? 0
                settings.style = all[(i + 1) % all.count]
            default:
                if let n = Int(press.characters), (0...9).contains(n) {
                    let all = LyricStyle.allCases
                    let idx = n == 0 ? 9 : n - 1
                    if idx < all.count { settings.style = all[idx] }
                } else {
                    return .ignored
                }
            }
        }
        revealChrome()
        return .handled
    }
}

/// Now-playing card for the presenter: artwork, title, artist and a thin progress bar.
struct AlbumCard: View {
    @ObservedObject var monitor = NowPlayingMonitor.shared

    var body: some View {
        HStack(spacing: 16) {
            ArtworkView(image: monitor.artwork, size: 96, corner: 12)
            VStack(alignment: .leading, spacing: 5) {
                Text(monitor.sample?.title ?? "").font(.system(size: 17, weight: .bold)).lineLimit(1)
                Text(monitor.sample?.artist ?? "").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let d = monitor.anchor.duration
                    let p = d > 0 ? monitor.position() / d : 0
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.15))
                                Capsule().fill(monitor.palette.map { Color(nsColor: $0.accent) } ?? .white)
                                    .frame(width: g.size.width * p)
                            }
                        }
                        .frame(height: 3)
                        HStack {
                            Text(formatTime(monitor.position()))
                            Spacer()
                            Text(monitor.sample?.player.displayName ?? "")
                        }
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .frame(width: 220)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}
