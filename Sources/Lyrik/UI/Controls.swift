import SwiftUI

/// The window's accent: the album's colour when one is known, otherwise Lyrik's own pink.
enum LyrikAccent {
    static let brand = Color(red: 0.93, green: 0.36, blue: 0.62)
    @MainActor static func current(_ monitor: NowPlayingMonitor) -> Color {
        monitor.palette.map { Color(nsColor: $0.accent) } ?? brand
    }
}

/// A capsule toggle: tinted with the accent when on.
struct ChipToggle: View {
    var title: String?
    var symbol: String
    @Binding var isOn: Bool
    var accent: Color = LyrikAccent.brand
    var help: String = ""

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                if let title { Text(title).font(.system(size: 11, weight: .semibold)) }
            }
            .padding(.horizontal, title == nil ? 7 : 10)
            .frame(height: 24)
            .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.55))
            .background(Capsule().fill(isOn ? accent.opacity(0.32) : Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(isOn ? accent.opacity(0.7) : Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .fixedSize()
        .help(help)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// Camera shake on/off, with the intensity one click away. Used in the window, the
/// presenter toolbar and anywhere else shake can be changed.
struct ShakeControl: View {
    @ObservedObject var settings = AppSettings.shared
    var accent: Color = LyrikAccent.brand
    var showsTitle = true

    var body: some View {
        HStack(spacing: 0) {
            Button { settings.shakeEnabled.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path").font(.system(size: 11, weight: .semibold))
                    if showsTitle { Text("Shake").font(.system(size: 11, weight: .semibold)) }
                }
                .padding(.leading, showsTitle ? 10 : 8)
                .padding(.trailing, 6)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .help(settings.shakeEnabled ? "Camera shake is on (K)" : "Camera shake is off (K)")

            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 14)

            Menu {
                ForEach(ShakeLevel.intensities) { level in
                    Button {
                        settings.shake = level
                        settings.shakeEnabled = true
                    } label: {
                        if settings.shake == level { Label(level.name, systemImage: "checkmark") } else { Text(level.name) }
                    }
                }
                Divider()
                Button(settings.shakeEnabled ? "Turn Off" : "Turn On") { settings.shakeEnabled.toggle() }
            } label: {
                (Text(settings.shake.name + " ").font(.system(size: 11, weight: .medium))
                 + Text(Image(systemName: "chevron.down")).font(.system(size: 8, weight: .bold)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .help("Shake intensity")
        }
        .frame(height: 26)
        .foregroundStyle(settings.shakeEnabled ? Color.white : Color.white.opacity(0.5))
        .background(RoundedRectangle(cornerRadius: 13, style: .circular)
            .fill(settings.shakeEnabled ? accent.opacity(0.32) : Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .circular)
            .strokeBorder(settings.shakeEnabled ? accent.opacity(0.7) : Color.white.opacity(0.1)))
        .fixedSize()
        .animation(.easeOut(duration: 0.15), value: settings.shakeEnabled)
    }
}
