import SwiftUI

/// How hard the camera reacts to the music.
enum ShakeLevel: String, CaseIterable, Identifiable, Codable {
    case off, subtle, punchy, intense
    var id: String { rawValue }
    var name: String {
        switch self {
        case .off: return "Off"
        case .subtle: return "Subtle"
        case .punchy: return "Punchy"
        case .intense: return "Intense"
        }
    }
    /// The choices offered once shake is switched on.
    static let intensities: [ShakeLevel] = [.subtle, .punchy, .intense]

    var gain: Double {
        switch self {
        case .off: return 0
        case .subtle: return 0.45
        case .punchy: return 1
        case .intense: return 1.8
        }
    }
}

/// A camera that is hit by every sung word: each onset kicks a short, decaying,
/// high-frequency shake (stronger for long words and the first word of a line),
/// layered over a slow handheld sway. Purely a function of lyric time, so every
/// view that shares the time shakes identically and nothing stutters.
struct CameraShake {
    var offset: CGSize
    var rotation: Double     // degrees
    var scale: CGFloat
    var energy: Double       // 0…1+, for effects that want to pulse with the hits

    static let still = CameraShake(offset: .zero, rotation: 0, scale: 1, energy: 0)

    /// - Parameters:
    ///   - frame: the lyric frame being drawn
    ///   - level: user setting
    ///   - extent: size of the view, so the shake scales with the screen
    static func at(_ frame: LyricFrame, level: ShakeLevel, extent: CGSize, reduceMotion: Bool) -> CameraShake {
        guard level != .off, !reduceMotion else { return .still }
        let t = frame.time
        let gain = level.gain
        let unit = Double(max(120, min(extent.width, extent.height))) / 900

        // Sum the decaying kicks of the words that landed in the last ~0.7 s.
        var energy = 0.0
        var phase = 0.0
        for (strength, start) in recentOnsets(frame) {
            let age = t - start
            guard age >= 0, age < 0.7 else { continue }
            // Fast attack, exponential release.
            let env = min(1, age / 0.018) * exp(-age * 7.5)
            energy += strength * env
            phase += start * 13.7
        }
        energy = min(energy, 2.2)

        // Band-limited "noise" from incommensurate sines; the phase changes per hit
        // so consecutive kicks push in different directions.
        func wobble(_ f1: Double, _ f2: Double, _ f3: Double, _ p: Double) -> Double {
            (sin(t * f1 + p) + 0.6 * sin(t * f2 + p * 1.7) + 0.35 * sin(t * f3 + p * 0.3)) / 1.95
        }
        let kickX = wobble(47, 71, 113, phase)
        let kickY = wobble(53, 83, 97, phase + 2.1)
        let kickR = wobble(37, 61, 89, phase + 4.2)

        // Slow handheld sway, always present while the level is on.
        let swayX = sin(t * 0.83) * 0.6 + sin(t * 1.91 + 1) * 0.4
        let swayY = sin(t * 0.67 + 2) * 0.6 + sin(t * 1.37) * 0.4
        let swayR = sin(t * 0.51 + 0.7)

        let dx = (kickX * 22 * energy + swayX * 3.2) * gain * unit
        let dy = (kickY * 17 * energy + swayY * 2.6) * gain * unit
        let rot = (kickR * 1.25 * energy + swayR * 0.25) * gain
        let punch = 1 + 0.025 * energy * gain

        return CameraShake(offset: CGSize(width: dx, height: dy), rotation: rot, scale: CGFloat(punch), energy: energy)
    }

    /// (strength, start) for the words around the playhead: this line and the end of the last one.
    private static func recentOnsets(_ f: LyricFrame) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        func add(_ line: LyricLine, lineHit: Bool) {
            for (k, w) in line.words.enumerated() where !w.display.isEmpty {
                var s = 0.55
                let n = w.display.count
                if n >= 6 { s += 0.25 }
                if n >= 9 { s += 0.15 }
                if w.display.hasSuffix("!") || w.display.uppercased() == w.display && n > 2 { s += 0.25 }
                if k == 0 && lineHit { s += 0.6 }   // a new line lands harder
                out.append((s, w.start))
            }
        }
        if let p = f.previous { add(p, lineHit: true) }
        if let c = f.current { add(c, lineHit: true) }
        return out
    }
}

extension View {
    /// Applies a camera shake transform.
    func cameraShake(_ s: CameraShake) -> some View {
        self
            .scaleEffect(s.scale)
            .rotationEffect(.degrees(s.rotation))
            .offset(s.offset)
    }
}
