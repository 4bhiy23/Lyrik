import AppKit
import SwiftUI

enum LyricStyle: String, CaseIterable, Identifiable, Codable {
    case stack
    case visual
    case fisheye
    case codestyle
    case flashbang
    case constellation
    case branches
    case wall
    case messages
    case notifications

    var id: String { rawValue }

    var name: String {
        switch self {
        case .stack: return "Stack"
        case .visual: return "Visual"
        case .fisheye: return "Fisheye"
        case .codestyle: return "Codestyle"
        case .flashbang: return "Flashbang"
        case .constellation: return "Constellation"
        case .branches: return "Branches"
        case .wall: return "Wall"
        case .messages: return "Messages"
        case .notifications: return "Notifications"
        }
    }

    var blurb: String {
        switch self {
        case .stack: return "The line before, the line now and the line next, filled word by word."
        case .visual: return "A centered stack, with an icon beside every word that has one."
        case .fisheye: return "Three words at a time, bulging through a glass lens."
        case .codestyle: return "Each line typed out as code under a blinking red cursor."
        case .flashbang: return "One word at a time, slammed across the whole screen."
        case .constellation: return "Every word a star, and the line traced between them."
        case .branches: return "A line draws itself, and each word lights a node on it."
        case .wall: return "Words land one by one on a wall that drifts in 3D."
        case .messages: return "The song as a chat thread, a bubble for every line."
        case .notifications: return "Lines arrive as notifications, stacking up the screen."
        }
    }

    var symbol: String {
        switch self {
        case .stack: return "text.alignleft"
        case .visual: return "square.grid.3x3.bottommiddle.filled"
        case .fisheye: return "circle.circle"
        case .codestyle: return "chevron.left.forwardslash.chevron.right"
        case .flashbang: return "bolt.fill"
        case .constellation: return "sparkles"
        case .branches: return "point.3.connected.trianglepath.dotted"
        case .wall: return "square.stack.3d.forward.dottedline"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .notifications: return "bell.badge.fill"
        }
    }

    /// Phone-screen styles draw with the system typeface and colors.
    var usesSystemLook: Bool { self == .messages || self == .notifications }
}

enum LyricFont: String, CaseIterable, Identifiable, Codable {
    case sfPro, sfRounded, newYork, helveticaNeue, avenirNext, futura, didot

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sfPro: return "SF Pro"
        case .sfRounded: return "SF Rounded"
        case .newYork: return "New York"
        case .helveticaNeue: return "Helvetica Neue"
        case .avenirNext: return "Avenir Next"
        case .futura: return "Futura"
        case .didot: return "Didot"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        switch self {
        case .sfPro: return .system(size: size, weight: weight, design: .default)
        case .sfRounded: return .system(size: size, weight: weight, design: .rounded)
        case .newYork: return .system(size: size, weight: weight, design: .serif)
        case .helveticaNeue: return .custom(weight == .regular ? "HelveticaNeue" : "HelveticaNeue-Bold", size: size)
        case .avenirNext: return .custom(weight == .regular ? "AvenirNext-Medium" : "AvenirNext-Bold", size: size)
        case .futura: return .custom(weight == .regular ? "Futura-Medium" : "Futura-Bold", size: size)
        case .didot: return .custom(weight == .regular ? "Didot" : "Didot-Bold", size: size)
        }
    }
}

enum UnlockedPlacement: String, CaseIterable, Identifiable, Codable {
    case overWindows, desktop
    var id: String { rawValue }
    var name: String { self == .overWindows ? "Over windows" : "On the desktop" }
}

/// Every user choice, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var style: LyricStyle { didSet { d.set(style.rawValue, forKey: "lyricStyle"); Log.write("style → \(style.name)") } }
    @Published var pinned: [LyricStyle] { didSet { d.set(pinned.map(\.rawValue), forKey: "pinnedStyles") } }
    @Published var size: Double { didSet { d.set(size, forKey: "textScale") } }
    @Published var font: LyricFont { didSet { d.set(font.rawValue, forKey: "font") } }
    @Published var textHex: String { didSet { d.set(textHex, forKey: "color.text") } }
    @Published var secondaryHex: String { didSet { d.set(secondaryHex, forKey: "color.secondary") } }
    @Published var highlightHex: String { didSet { d.set(highlightHex, forKey: "color.highlight") } }
    @Published var matchArtwork: Bool { didSet { d.set(matchArtwork, forKey: "matchArtwork") } }
    @Published var lockScreen: Bool { didSet { d.set(lockScreen, forKey: "lockScreen") } }
    @Published var showWhenUnlocked: Bool { didSet { d.set(showWhenUnlocked, forKey: "showWhenUnlocked") } }
    @Published var unlockedPlacement: UnlockedPlacement { didSet { d.set(unlockedPlacement.rawValue, forKey: "unlockedPlacement") } }
    @Published var keepAwake: Bool { didSet { d.set(keepAwake, forKey: "keepAwake") } }
    @Published var disabledDisplays: [String] { didSet { d.set(disabledDisplays, forKey: "disabledDisplays") } }
    @Published var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: "onboardingDone") } }
    @Published var dimBackdrop: Bool { didSet { d.set(dimBackdrop, forKey: "dimBackdrop") } }
    /// A soft album-tinted glow around the edges of full-screen lyrics.
    @Published var edgeGlow: Bool { didSet { d.set(edgeGlow, forKey: "edgeGlow") } }
    /// Camera shake on every sung word, across all styles and surfaces.
    @Published var shakeEnabled: Bool { didSet { d.set(shakeEnabled, forKey: "shakeEnabled"); Log.write("shake \(shakeEnabled ? "on" : "off")") } }
    /// How hard it shakes when on (never `.off`).
    @Published var shake: ShakeLevel { didSet { d.set(shake.rawValue, forKey: "shake"); Log.write("shake → \(shake.name)") } }
    /// What the renderer should use right now.
    var effectiveShake: ShakeLevel { shakeEnabled ? shake : .off }
    /// Presenter window: show the album card beside the lyrics.
    @Published var presentShowsCard: Bool { didSet { d.set(presentShowsCard, forKey: "presentShowsCard") } }

    private init() {
        style = LyricStyle(rawValue: d.string(forKey: "lyricStyle") ?? "") ?? .stack
        pinned = (d.stringArray(forKey: "pinnedStyles") ?? ["stack", "fisheye", "messages"]).compactMap(LyricStyle.init(rawValue:))
        size = d.object(forKey: "textScale") as? Double ?? 1.0
        font = LyricFont(rawValue: d.string(forKey: "font") ?? "") ?? .sfPro
        textHex = d.string(forKey: "color.text") ?? "#FFFFFFFF"
        secondaryHex = d.string(forKey: "color.secondary") ?? "#FFFFFF8C"
        highlightHex = d.string(forKey: "color.highlight") ?? "#FFFFFFFF"
        matchArtwork = d.object(forKey: "matchArtwork") as? Bool ?? true
        lockScreen = d.object(forKey: "lockScreen") as? Bool ?? true
        showWhenUnlocked = d.object(forKey: "showWhenUnlocked") as? Bool ?? false
        unlockedPlacement = UnlockedPlacement(rawValue: d.string(forKey: "unlockedPlacement") ?? "") ?? .desktop
        keepAwake = d.object(forKey: "keepAwake") as? Bool ?? false
        disabledDisplays = d.stringArray(forKey: "disabledDisplays") ?? []
        onboardingDone = d.bool(forKey: "onboardingDone")
        dimBackdrop = d.object(forKey: "dimBackdrop") as? Bool ?? true
        edgeGlow = d.object(forKey: "edgeGlow") as? Bool ?? true
        let storedShake = ShakeLevel(rawValue: d.string(forKey: "shake") ?? "") ?? .punchy
        shake = storedShake == .off ? .punchy : storedShake
        shakeEnabled = d.object(forKey: "shakeEnabled") as? Bool ?? (storedShake != .off)
        presentShowsCard = d.object(forKey: "presentShowsCard") as? Bool ?? true
    }

    func togglePin(_ s: LyricStyle) {
        if let i = pinned.firstIndex(of: s) { pinned.remove(at: i) } else { pinned.append(s) }
    }

    func resetColors() {
        textHex = "#FFFFFFFF"
        secondaryHex = "#FFFFFF8C"
        highlightHex = "#FFFFFFFF"
    }
}

/// Colors and type resolved for drawing right now (settings + album art).
struct LyricTheme {
    var text: Color
    var secondary: Color
    var highlight: Color
    var accent: Color
    var backdrop: Color
    var font: LyricFont
    var scale: CGFloat
    /// True while the user has not picked their own text color.
    var textIsDefault: Bool

    func font(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        font.font(size: size * scale, weight: weight)
    }

    @MainActor
    static func current(settings: AppSettings, palette: ArtworkPalette?) -> LyricTheme {
        let text = NSColor(hexRGBA: settings.textHex) ?? .white
        let secondary = NSColor(hexRGBA: settings.secondaryHex) ?? NSColor.white.withAlphaComponent(0.55)
        var highlight = NSColor(hexRGBA: settings.highlightHex) ?? .white
        var accent = NSColor.systemPink
        var backdrop = NSColor.black
        if settings.matchArtwork, let p = palette {
            highlight = p.accent
            accent = p.accent
            backdrop = p.background
        }
        return LyricTheme(text: Color(nsColor: text), secondary: Color(nsColor: secondary), highlight: Color(nsColor: highlight),
                          accent: Color(nsColor: accent), backdrop: Color(nsColor: backdrop),
                          font: settings.font, scale: CGFloat(settings.size),
                          textIsDefault: settings.textHex.uppercased() == "#FFFFFFFF")
    }
}
