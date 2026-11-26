import Foundation

/// Original placeholder verses used only to preview styles when no song has lyrics.
/// They are labelled as a preview in the UI and never shown on the lock screen.
enum DemoLyrics {
    static let verses = [
        "Neon rivers run beneath the city rain",
        "I hear your voice in every passing train",
        "Light a little fire on the edge of night",
        "Hold the moon until the morning light",
        "Call my phone when all the stars are out",
        "We could dance until the summer burns out",
        "Paper hearts are flying through the sky",
        "Sing it loud and let the world go by",
    ]

    static let lines: [LyricLine] = {
        var t = 0.6
        var out: [LyricLine] = []
        for (i, text) in verses.enumerated() {
            let words = LyricParsers.interpolate(text, start: t, limit: t + 3.4)
            out.append(LyricLine(id: i, start: t, end: t + 3.6, text: text, words: words))
            t += 3.6
        }
        return out
    }()

    static var length: Double { (lines.last?.end ?? 1) + 0.4 }

    static func frame(at uptime: Double) -> LyricFrame {
        LyricFrame.make(lines: lines, time: uptime.truncatingRemainder(dividingBy: length))
    }
}
