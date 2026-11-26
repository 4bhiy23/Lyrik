import SwiftUI

func formatTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s.rounded(.down))
    return String(format: "%d:%02d", t / 60, t % 60)
}

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.03)
        .animation(.easeInOut(duration: 0.35), value: image)
    }
}

/// Elapsed / remaining with a draggable bar that seeks the player on release.
struct ProgressScrubber: View {
    @ObservedObject var monitor = NowPlayingMonitor.shared
    var tint: Color = .white
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let duration = monitor.anchor.duration
            let pos = monitor.position()
            let fraction = duration > 0 ? pos / duration : 0
            VStack(spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(tint).frame(width: max(0, g.size.width * fraction))
                    }
                    .frame(height: hovering || monitor.scrubbing != nil ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard duration > 0 else { return }
                            monitor.scrubbing = (v.location.x / g.size.width).clamped() * duration
                        }
                        .onEnded { v in
                            guard duration > 0 else { return }
                            let target = (v.location.x / g.size.width).clamped() * duration
                            monitor.scrubbing = nil
                            monitor.seek(to: target)
                        })
                    .onHover { hovering = $0 }
                    .animation(.easeOut(duration: 0.15), value: hovering)
                }
                .frame(height: 12)
                HStack {
                    Text(formatTime(pos))
                    Spacer()
                    Text("-" + formatTime(max(0, duration - pos)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }
            .disabled(monitor.sample == nil)
        }
    }
}

struct TransportControls: View {
    @ObservedObject var monitor = NowPlayingMonitor.shared
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: size * 1.4) {
            TransportButton(symbol: "backward.fill", size: size) { monitor.previous() }
            TransportButton(symbol: monitor.isPlaying ? "pause.fill" : "play.fill", size: size * 1.45) { monitor.playPause() }
                .contentTransition(.symbolEffect(.replace))
            TransportButton(symbol: "forward.fill", size: size) { monitor.next() }
        }
        .disabled(monitor.sample == nil && !PlayerKind.allCases.contains(where: { $0.isRunning }))
    }
}

struct TransportButton: View {
    var symbol: String
    var size: CGFloat
    var action: () -> Void
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size * 2, height: size * 2)
                .background(Circle().fill(.white.opacity(hover ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .foregroundStyle(.white)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct VolumeSlider: View {
    @ObservedObject var monitor = NowPlayingMonitor.shared
    @State private var value: Double = 50
    @State private var editing = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            Slider(value: $value, in: 0...100) { e in
                editing = e
                if !e { monitor.setVolume(Int(value)) }
            }
            .controlSize(.mini)
            .tint(.white)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        }
        .onAppear { value = Double(monitor.sample?.volume ?? 50) }
        .onChange(of: monitor.sample?.volume) { _, v in if !editing, let v { value = Double(v) } }
        .disabled(monitor.sample?.volume == nil)
    }
}

/// Per-song timing shift: earlier / reset / later.
struct LyricTimingControl: View {
    @ObservedObject var engine = LyricEngine.shared

    var body: some View {
        HStack(spacing: 6) {
            Button { engine.shift(by: 0.5) } label: { Label("Earlier", systemImage: "backward.end.alt.fill").labelStyle(.iconOnly) }
                .help("Show the lyrics half a second earlier")
            Button { engine.resetShift() } label: {
                Text(engine.offset == 0 ? "On time"
                     : String(format: "%.1fs %@", abs(engine.offset), engine.offset > 0 ? "early" : "late"))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .frame(minWidth: 64)
            }
            .help("Back to the lyrics' own timing")
            Button { engine.shift(by: -0.5) } label: { Label("Later", systemImage: "forward.end.alt.fill").labelStyle(.iconOnly) }
                .help("Show the lyrics half a second later")
        }
        .buttonStyle(GlassPillButtonStyle(compact: true))
        .disabled(engine.lyrics == nil)
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    var compact = false
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 6)
            .background(Capsule().fill(prominent ? Color.white.opacity(configuration.isPressed ? 0.75 : 0.92) : Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.1)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: Player status

struct PlayerHealth {
    enum Level { case good, waiting, problem, off }
    var level: Level
    var title: String
    var detail: String
    var fix: Fix?

    enum Fix { case allow, openSettings, reset, launch }

    var color: Color {
        switch level {
        case .good: return .green
        case .waiting: return .yellow
        case .problem: return .red
        case .off: return .gray
        }
    }

    @MainActor
    static func of(_ player: PlayerKind, monitor: NowPlayingMonitor) -> PlayerHealth {
        let name = player.displayName
        let read = monitor.reads[player]
        let access = monitor.access[player] ?? .unknown
        switch read {
        case .notInstalled:
            return PlayerHealth(level: .off, title: "Not installed", detail: "\(name) is not on this Mac.", fix: nil)
        case .closed, .none:
            return PlayerHealth(level: .off, title: "Closed", detail: "Open \(name) and play something.", fix: .launch)
        case .denied:
            return PlayerHealth(level: .problem, title: "Blocked in System Settings",
                                detail: "Allow Lyrik under Privacy & Security › Automation › \(name).", fix: .openSettings)
        case .needsConsent:
            return PlayerHealth(level: .waiting, title: "Needs your permission",
                                detail: "macOS asks once. Choose Allow.", fix: .allow)
        case .failed(let code, _):
            return PlayerHealth(level: .problem, title: "Not answering",
                                detail: "\(name) answered with error \(code). Quitting and reopening it usually clears it.", fix: .reset)
        case .idle:
            return PlayerHealth(level: .good, title: "Connected", detail: "\(name) is open with nothing playing.", fix: nil)
        case .sample(let s):
            if s.position == nil {
                return PlayerHealth(level: .waiting, title: "No playhead", detail: "\(name) did not say where the song is.", fix: nil)
            }
            _ = access
            return PlayerHealth(level: .good, title: s.state == .playing ? "Playing" : "Paused",
                                detail: s.title.isEmpty ? "Something without a title." : "\(s.title) — \(s.artist)", fix: nil)
        }
    }
}

struct PlayerStatusRow: View {
    var player: PlayerKind
    @ObservedObject var monitor = NowPlayingMonitor.shared

    var body: some View {
        let health = PlayerHealth.of(player, monitor: monitor)
        HStack(spacing: 10) {
            if let icon = player.icon {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            } else {
                Image(systemName: "music.note").frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.displayName).font(.system(size: 12, weight: .semibold))
                    Circle().fill(health.color).frame(width: 6, height: 6)
                    Text(health.title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
                Text(health.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
            }
            Spacer(minLength: 6)
            if let fix = health.fix {
                Button(fixLabel(fix)) { perform(fix) }
                    .buttonStyle(GlassPillButtonStyle(compact: true, prominent: fix == .allow))
            }
        }
    }

    private func fixLabel(_ fix: PlayerHealth.Fix) -> String {
        switch fix {
        case .allow: return "Allow"
        case .openSettings: return "Open Settings"
        case .reset: return "Ask again"
        case .launch: return "Open"
        }
    }

    private func perform(_ fix: PlayerHealth.Fix) {
        switch fix {
        case .allow:
            monitor.requestAccess(player)
        case .openSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        case .reset:
            PermissionReset.reset(then: { monitor.forgetAccess(); monitor.requestAccess(player) })
        case .launch:
            if let url = player.appURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
}

enum PermissionReset {
    /// Clears Lyrik's Apple Events answers so macOS asks again.
    static func reset(then: @escaping @MainActor () -> Void) {
        guard let id = Bundle.main.bundleIdentifier else { return }
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", "AppleEvents", id]
            do { try p.run(); p.waitUntilExit() } catch { Log.write("tccutil failed: \(error)") }
            Log.write("automation answers reset (\(p.terminationStatus))")
            DispatchQueue.main.async { then() }
        }
    }
}
