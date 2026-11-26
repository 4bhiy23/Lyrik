import AppKit
import SwiftUI

@MainActor
final class GalleryWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Lyrik"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 960, height: 620)
        window.backgroundColor = NSColor(white: 0.05, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: GalleryView())
        window.setContentSize(NSSize(width: 1180, height: 740))
        window.center()
        window.setFrameAutosaveName("LyrikGallery")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum GalleryTab: String, CaseIterable, Identifiable {
    case styles = "Styles", look = "Look", lock = "Lock Screen", players = "Players"
    var id: String { rawValue }
    var short: String { self == .lock ? "Lock" : rawValue }
    var symbol: String {
        switch self {
        case .styles: return "square.grid.2x2"
        case .look: return "paintbrush.pointed"
        case .lock: return "lock"
        case .players: return "music.note.list"
        }
    }
}

struct GalleryView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var monitor = NowPlayingMonitor.shared
    @ObservedObject var engine = LyricEngine.shared
    @State private var tab: GalleryTab = .styles
    @State private var hovered: LyricStyle?
    @Namespace private var tabSpace

    static let inspectorWidth: CGFloat = 340

    var body: some View {
        let accent = LyrikAccent.current(monitor)
        ZStack {
            windowBackdrop(accent)

            VStack(spacing: 14) {
                NowPlayingBar(accent: accent) { tab = .players }
                HStack(alignment: .top, spacing: 14) {
                    stage(accent)
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    inspector(accent)
                        .frame(width: Self.inspectorWidth)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 38)
            .padding(.bottom, 18)

            if !settings.onboardingDone {
                OnboardingView().transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.35), value: settings.onboardingDone)
    }

    private func windowBackdrop(_ accent: Color) -> some View {
        ZStack {
            Color(white: 0.05)
            RadialGradient(colors: [accent.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [accent.opacity(0.06), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: monitor.palette)
    }

    // MARK: Stage

    private func stage(_ accent: Color) -> some View {
        let shown = hovered ?? settings.style
        return VStack(spacing: 10) {
            ZStack {
                heroBackdrop
                LyricStageView(mode: .preview(compact: false), styleOverride: shown, allowDemo: true)
                    .padding(28)
                if engine.lyrics == nil {
                    VStack {
                        HStack {
                            Label("Sample words", systemImage: "text.quote")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.4)))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

            captionBar(shown, accent)
        }
    }

    private var heroBackdrop: some View {
        ZStack {
            let bg = monitor.palette.map { Color(nsColor: $0.background) } ?? Color(red: 0.07, green: 0.08, blue: 0.15)
            LinearGradient(colors: [bg, .black], startPoint: .top, endPoint: .bottom)
            // Bounded so the cover never sizes the stage (scaledToFill would overflow it).
            Color.clear.overlay {
                if let art = monitor.artwork {
                    Image(nsImage: art).resizable().scaledToFill().blur(radius: 90).opacity(0.3)
                }
            }
            .clipped()
            // A quiet stand-in for the lock screen clock, so the placement reads true.
            VStack(spacing: 0) {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 10, weight: .semibold))
                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.13))
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 14)
        }
    }

    private func captionBar(_ shown: LyricStyle, _ accent: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: shown.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(shown.name).font(.system(size: 13, weight: .semibold))
                    if hovered != nil, hovered != settings.style {
                        Text("PREVIEW").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().strokeBorder(.white.opacity(0.25)))
                    }
                }
                Text(engine.lyrics == nil ? engine.status.headline : shown.blurb)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)

            if engine.lyrics != nil {
                LyricTimingControl().fixedSize()
            } else if monitor.sample != nil, engine.status != .looking {
                Button("Look again") { engine.lookAgain() }
                    .buttonStyle(GlassPillButtonStyle(compact: true)).fixedSize()
            }
            ShakeControl(accent: accent)
        }
        .padding(.leading, 8).padding(.trailing, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    // MARK: Inspector

    private func inspector(_ accent: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(GalleryTab.allCases) { t in
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = t } } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.symbol).font(.system(size: 13, weight: .semibold))
                            Text(t.short).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(tab == t ? Color.white : Color.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            if tab == t {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white.opacity(0.1))
                                    .matchedGeometryEffect(id: "tab", in: tabSpace)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.rawValue)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black.opacity(0.25)))
            .padding(12)

            ScrollView {
                Group {
                    switch tab {
                    case .styles: StyleShelf(hovered: $hovered, accent: accent)
                    case .look: LookPanel(accent: accent)
                    case .lock: LockScreenPanel()
                    case .players: PlayersPanel()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.085)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: Now playing bar

struct NowPlayingBar: View {
    var accent: Color
    var showPlayers: () -> Void
    @ObservedObject var monitor = NowPlayingMonitor.shared

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(image: monitor.artwork, size: 46, corner: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.sample?.title ?? "Nothing playing")
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(monitor.sample?.artist ?? "Play a song in Spotify or Apple Music")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            .frame(minWidth: 110, maxWidth: 230, alignment: .leading)

            TransportControls(size: 12).fixedSize()

            ProgressScrubber(tint: accent)
                .frame(minWidth: 120, maxWidth: .infinity)

            HStack(spacing: 6) {
                ForEach(PlayerKind.allCases) { PlayerChip(player: $0, action: showPlayers) }
            }
            .fixedSize()

            Button { PresentWindowController.shared.present() } label: {
                Label("Present", systemImage: "play.display").fixedSize()
            }
            .buttonStyle(GlassPillButtonStyle(prominent: true))
            .fixedSize()
            .help("Show the lyrics in a window you can share in a call or put on another display")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

/// A player's icon with a status dot; the name and state are in the tooltip.
struct PlayerChip: View {
    var player: PlayerKind
    var action: () -> Void
    @ObservedObject var monitor = NowPlayingMonitor.shared
    @State private var hover = false

    var body: some View {
        let h = PlayerHealth.of(player, monitor: monitor)
        let active = monitor.sample?.player == player
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon = player.icon { Image(nsImage: icon).resizable() }
                    else { Image(systemName: "music.note").resizable().scaledToFit().padding(4) }
                }
                .frame(width: 22, height: 22)
                .opacity(h.level == .off ? 0.45 : 1)
                Circle().fill(h.color)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Color(white: 0.08), lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
            .padding(5)
            .background(Circle().fill(.white.opacity(active ? 0.14 : (hover ? 0.1 : 0.05))))
            .overlay(Circle().strokeBorder(.white.opacity(active ? 0.25 : 0)))
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
        .help("\(player.displayName): \(h.title). \(h.detail)")
    }
}

// MARK: Styles

struct StyleShelf: View {
    @Binding var hovered: LyricStyle?
    var accent: Color
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(LyricStyle.allCases) { style in
                    StyleTile(style: style, selected: settings.style == style, pinned: settings.pinned.contains(style),
                              live: hovered == style || settings.style == style, accent: accent)
                        .onHover { inside in
                            if inside { hovered = style } else if hovered == style { hovered = nil }
                        }
                        .onTapGesture { settings.style = style }
                }
            }
            Label("Pinned styles show in the menu bar for quick switching.", systemImage: "pin")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 2)
        }
    }
}

struct StyleTile: View {
    var style: LyricStyle
    var selected: Bool
    var pinned: Bool
    var live: Bool
    var accent: Color
    @ObservedObject var settings = AppSettings.shared
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.09, green: 0.1, blue: 0.17), .black], startPoint: .top, endPoint: .bottom)
            LyricStageView(mode: .preview(compact: true), styleOverride: style, allowDemo: true, animating: live)
                .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 26)

            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            HStack(spacing: 5) {
                Image(systemName: style.symbol).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? accent : .white.opacity(0.7))
                Text(style.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.bottom, 7)
        }
        .frame(height: 112)
        .overlay(alignment: .topTrailing) {
            if hover || pinned {
                Button { settings.togglePin(style) } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(pinned ? accent : .white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(pinned ? "Unpin from the menu bar" : "Pin to the menu bar")
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? accent : Color.white.opacity(hover ? 0.22 : 0.08), lineWidth: selected ? 2 : 1))
        .shadow(color: selected ? accent.opacity(0.35) : .clear, radius: 10)
        .scaleEffect(hover && !selected ? 1.02 : 1)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(.easeOut(duration: 0.2), value: selected)
        .help(style.blurb)
    }
}

// MARK: Look

struct LookPanel: View {
    var accent: Color = LyrikAccent.brand
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelSection("Motion") {
                SettingSwitch(title: "Camera shake", detail: "The camera reacts to every sung word, in every style.", isOn: $settings.shakeEnabled)
                Picker("", selection: $settings.shake) {
                    ForEach(ShakeLevel.intensities) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!settings.shakeEnabled)
                .opacity(settings.shakeEnabled ? 1 : 0.4)
                SettingSwitch(title: "Edge glow", detail: "A neon rim that pulses with the words, full screen only.", isOn: $settings.edgeGlow)
                Text("Shake and glow stay still when Reduce Motion is on.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            PanelSection("Size") {
                HStack {
                    Image(systemName: "textformat.size.smaller")
                    Slider(value: $settings.size, in: 0.6...1.6).tint(accent)
                    Image(systemName: "textformat.size.larger")
                }
                .foregroundStyle(.white.opacity(0.6))
            }
            PanelSection("Font") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(LyricFont.allCases) { f in
                        Button { settings.font = f } label: {
                            Text(f.name).font(f.font(size: 13, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassPillButtonStyle(prominent: settings.font == f))
                    }
                }
                Text("Messages and Notifications always use the system typeface.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            PanelSection("Colors") {
                SettingSwitch(title: "Match the album cover", detail: "The highlight follows whatever is playing.", isOn: $settings.matchArtwork)
                ColorRow(title: "Text", hex: $settings.textHex)
                ColorRow(title: "Upcoming words", hex: $settings.secondaryHex)
                ColorRow(title: "Highlight", hex: $settings.highlightHex)
                    .disabled(settings.matchArtwork)
                    .opacity(settings.matchArtwork ? 0.4 : 1)
                Button("Reset colors") { settings.resetColors() }.buttonStyle(GlassPillButtonStyle(compact: true))
            }
            PanelSection("Backdrop") {
                SettingSwitch(title: "Dim behind the words", detail: "A soft shade tinted by the album, for legibility.", isOn: $settings.dimBackdrop)
            }
        }
    }
}

struct ColorRow: View {
    var title: String
    @Binding var hex: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor(hexRGBA: hex) ?? .white) },
                set: { hex = NSColor($0).hexRGBA }), supportsOpacity: true)
            .labelsHidden()
        }
    }
}

// MARK: Lock screen

struct LockScreenPanel: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var lock = LockMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelSection("Lock screen") {
                SettingSwitch(title: "Lyrics on the lock screen", detail: SkyLightSpace.shared.isAvailable
                              ? "Lock the screen with a song on to see them."
                              : "This macOS did not allow drawing above the lock screen.", isOn: $settings.lockScreen)
                SettingSwitch(title: "Keep the screen awake", detail: "While music is playing.", isOn: $settings.keepAwake)
            }
            PanelSection("While unlocked") {
                SettingSwitch(title: "Show lyrics while unlocked", detail: "Off keeps them to the lock screen.", isOn: $settings.showWhenUnlocked)
                Picker("Placement", selection: $settings.unlockedPlacement) {
                    ForEach(UnlockedPlacement.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.showWhenUnlocked)
                Text("On the desktop sits behind your windows; over windows floats above them and lets clicks through.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            PanelSection("Displays") {
                ForEach(NSScreen.screens, id: \.localizedName) { screen in
                    let key = OverlayController.displayKey(screen)
                    Toggle(screen.localizedName, isOn: Binding(
                        get: { !settings.disabledDisplays.contains(key) },
                        set: { on in
                            if on { settings.disabledDisplays.removeAll { $0 == key } }
                            else if !settings.disabledDisplays.contains(key) { settings.disabledDisplays.append(key) }
                        }))
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12))
                }
            }
        }
    }
}

// MARK: Players

struct PlayersPanel: View {
    @ObservedObject var monitor = NowPlayingMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelSection("Players") {
                ForEach(PlayerKind.allCases) { PlayerStatusRow(player: $0) }
                Text("Lyrik follows whichever player is playing, and Spotify if both are. Songs playing in a browser or on another device do not count.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            PanelSection("Permission") {
                Text("Lyrik reads the song and the playhead from each player over Apple Events. macOS asks once per player.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                HStack {
                    Button("Open Automation settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    Button("Ask again") {
                        PermissionReset.reset { monitor.forgetAccess(); PlayerKind.allCases.filter(\.isRunning).forEach { monitor.requestAccess($0) } }
                    }
                }
                .buttonStyle(GlassPillButtonStyle(compact: true))
            }
            PanelSection("Diagnostics") {
                Button("Show log") { NSWorkspace.shared.open(Log.fileURL) }
                    .buttonStyle(GlassPillButtonStyle(compact: true))
            }
        }
    }
}

// MARK: Building blocks

struct PanelSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.05)))
    }
}

struct SettingSwitch: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
