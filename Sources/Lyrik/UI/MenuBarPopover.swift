import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var monitor = NowPlayingMonitor.shared
    @ObservedObject var engine = LyricEngine.shared
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var lock = LockMonitor.shared
    var openWindow: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if monitor.sample != nil {
                ProgressScrubber(tint: tint)
                HStack {
                    Spacer()
                    TransportControls(size: 16)
                    Spacer()
                }
                VolumeSlider()
            }
            lyricCard
            stylesRow
            Divider().overlay(.white.opacity(0.1))
            toggles
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(background)
        .environment(\.colorScheme, .dark)
    }

    private var tint: Color {
        if let p = monitor.palette { return Color(nsColor: p.accent) }
        return .white
    }

    private var header: some View {
        HStack(spacing: 12) {
            ArtworkView(image: monitor.artwork, size: 64, corner: 10)
            VStack(alignment: .leading, spacing: 3) {
                if let s = monitor.sample {
                    Text(s.title.isEmpty ? "Untitled" : s.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Text(s.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(s.state == .playing ? Color.green : Color.yellow).frame(width: 6, height: 6)
                        Text("\(s.state == .playing ? "Playing" : "Paused") in \(s.player.displayName)")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                } else {
                    Text("Nothing playing").font(.system(size: 14, weight: .semibold))
                    Text("Play a song in Spotify or Apple Music.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var lyricCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !monitor.isPlaying)) { _ in
                let f = engine.frame()
                let shake = CameraShake.at(f, level: settings.effectiveShake, extent: CGSize(width: 300, height: 300), reduceMotion: false)
                VStack(alignment: .leading, spacing: 4) {
                    if engine.lyrics != nil {
                        Text(f.current?.isBreak == false ? f.current!.text : "♪")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .cameraShake(shake)
                            .id(f.index ?? -1)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                        Text(f.next?.text ?? " ")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    } else {
                        Text(engine.status.headline).font(.system(size: 13, weight: .semibold))
                        Text(engine.status.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.25), value: f.index)
            }
            if engine.lyrics != nil {
                HStack {
                    Text(engine.status.headline).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    Spacer()
                    LyricTimingControl()
                }
            } else if monitor.sample != nil, engine.status != .looking {
                Button("Look again") { engine.lookAgain() }.buttonStyle(GlassPillButtonStyle(compact: true))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
    }

    private var stylesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STYLE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            let styles = settings.pinned.isEmpty ? [settings.style] : settings.pinned
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(styles) { s in
                        Button { settings.style = s } label: {
                            Label(s.name, systemImage: s.symbol)
                        }
                        .buttonStyle(GlassPillButtonStyle(compact: true, prominent: settings.style == s))
                    }
                    Button { openWindow() } label: { Image(systemName: "ellipsis") }
                        .buttonStyle(GlassPillButtonStyle(compact: true))
                        .help("All styles")
                }
            }
        }
    }

    private var toggles: some View {
        VStack(spacing: 8) {
            toggleRow("Lyrics on the lock screen", $settings.lockScreen)
            toggleRow("Show lyrics while unlocked", $settings.showWhenUnlocked)
            toggleRow("Keep the screen awake while playing", $settings.keepAwake)
            HStack {
                Text("Camera shake").font(.system(size: 12))
                Spacer()
                if settings.shakeEnabled {
                    Picker("", selection: $settings.shake) {
                        ForEach(ShakeLevel.intensities) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .controlSize(.mini)
                    .transition(.opacity)
                }
                Toggle("", isOn: $settings.shakeEnabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            .animation(.easeOut(duration: 0.15), value: settings.shakeEnabled)
        }
    }

    private func toggleRow(_ title: String, _ value: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Lyrik") { openWindow() }.buttonStyle(GlassPillButtonStyle(compact: true))
            Button { PresentWindowController.shared.present() } label: { Label("Present", systemImage: "play.display") }
                .buttonStyle(GlassPillButtonStyle(compact: true))
                .help("Show the lyrics in a window you can share or put on another display")
            Spacer()
            Button("Quit") { quit() }.buttonStyle(GlassPillButtonStyle(compact: true))
        }
    }

    private var background: some View {
        ZStack {
            Color(white: 0.08)
            if let art = monitor.artwork {
                Image(nsImage: art).resizable().scaledToFill()
                    .blur(radius: 60).opacity(0.45)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.5), value: monitor.artwork)
    }
}
