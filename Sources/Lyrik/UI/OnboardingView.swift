import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, players, style }

    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var monitor = NowPlayingMonitor.shared
    @State private var step: Step = .welcome

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 22) {
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.rawValue) { s in
                        Capsule().fill(s.rawValue <= step.rawValue ? Color.white : Color.white.opacity(0.2))
                            .frame(width: s == step ? 22 : 8, height: 6)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)

                Group {
                    switch step {
                    case .welcome: welcome
                    case .players: players
                    case .style: styles
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxWidth: 560)
            }
            .padding(36)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(white: 0.1)))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.5), radius: 40)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: step)
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            AppGlyph().frame(width: 84, height: 84)
            Text("Lyrics on your lock screen, word by word").font(.system(size: 22, weight: .bold)).multilineTextAlignment(.center)
            Text("Lyrik follows what is playing in Spotify or Apple Music and sets the words over your lock screen as they are sung. Its menu bar panel also controls the player.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            Button("Get started") { step = .players }.buttonStyle(GlassPillButtonStyle(prominent: true)).padding(.top, 6)
        }
    }

    private var players: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Let Lyrik hear your music").font(.system(size: 22, weight: .bold))
            Text("Lyrik reads the song and where it is from your player. macOS asks once for each one. Open the player you use and choose Allow — either is enough.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            VStack(spacing: 12) {
                ForEach(PlayerKind.allCases) { PlayerStatusRow(player: $0) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
            HStack {
                Button("Back") { step = .welcome }.buttonStyle(GlassPillButtonStyle())
                Spacer()
                Button("Continue") { step = .style }.buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
        .onAppear {
            monitor.mayAskForConsent = true
            monitor.poll()
        }
    }

    private var styles: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick how the lyrics look").font(.system(size: 22, weight: .bold))
            Text("Ten styles. Change it any time, here or from the menu bar.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(LyricStyle.allCases) { s in
                    Button { settings.style = s } label: {
                        VStack(spacing: 6) {
                            Image(systemName: s.symbol).font(.system(size: 18))
                            Text(s.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(RoundedRectangle(cornerRadius: 10).fill(settings.style == s ? Color.white.opacity(0.9) : Color.white.opacity(0.06)))
                        .foregroundStyle(settings.style == s ? Color.black : Color.white)
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            Text(settings.style.blurb).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            HStack {
                Button("Back") { step = .players }.buttonStyle(GlassPillButtonStyle())
                Spacer()
                Button("Done") {
                    settings.onboardingDone = true
                    monitor.mayAskForConsent = true
                    Log.write("onboarding finished")
                }
                .buttonStyle(GlassPillButtonStyle(prominent: true))
            }
        }
    }
}

/// The app's mark, drawn in code: three lyric lines inside a speech bubble,
/// the middle one lit as if being sung.
struct AppGlyph: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.47), Color(red: 0.42, green: 0.2, blue: 0.86)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: s * 0.07) {
                    Capsule().fill(.white.opacity(0.45)).frame(width: s * 0.36, height: s * 0.075)
                    Capsule().fill(.white).frame(width: s * 0.56, height: s * 0.1)
                    Capsule().fill(.white.opacity(0.45)).frame(width: s * 0.44, height: s * 0.075)
                }
                .offset(x: -s * 0.02)
            }
        }
    }
}
