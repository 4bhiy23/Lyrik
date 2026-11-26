import Foundation

struct TimedWord: Codable, Equatable, Hashable {
    var start: Double
    var end: Double
    /// Raw text, keeping any trailing space so lines can be rebuilt exactly.
    var text: String

    var display: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct LyricLine: Codable, Equatable, Identifiable, Hashable {
    var id: Int
    var start: Double
    var end: Double
    var text: String
    var words: [TimedWord]

    var isBreak: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

struct TimedLyrics: Codable, Equatable {
    var lines: [LyricLine]
    var source: String          // "lrclib" / "netease"
    var wordLevel: Bool         // true when the source timed each word
    var lengthGap: Double       // source length minus playing length, seconds
}

enum LyricStatus: Equatable {
    case idle
    case noTitle
    case looking
    case found(source: String, wordLevel: Bool, gap: Double)
    case instrumental
    case untimed
    case otherLength(Double)
    case notFound
    case unreachable

    var headline: String {
        switch self {
        case .idle: return "Nothing playing"
        case .noTitle: return "No lyrics without a title"
        case .looking: return "Looking for lyrics"
        case .found(_, let word, let gap):
            if abs(gap) >= 1.5 { return String(format: "Lyrics found, from a version %+.0fs in length", gap) }
            return word ? "Lyrics found, timed word by word" : "Lyrics found, timed line by line"
        case .instrumental: return "Listed as an instrumental"
        case .untimed: return "This song's lyrics are not timed yet"
        case .otherLength: return "Lyrics found only for another version"
        case .notFound: return "No lyrics found for this song"
        case .unreachable: return "Could not reach the lyric sources"
        }
    }

    var detail: String {
        switch self {
        case .idle: return "Play something in Spotify or Apple Music."
        case .noTitle: return "Radio and some streams do not name the song, so there is nothing to look up."
        case .looking: return "Asking LRCLIB and NetEase."
        case .found(let source, _, let gap):
            let name = source == "netease" ? "NetEase" : "LRCLIB"
            if abs(gap) >= 1.5 { return "From \(name). If the words run early or late, shift them below." }
            return "From \(name)."
        case .instrumental: return "The lyric sources say it has no words."
        case .untimed: return "The sources list it without timings, so the words cannot be placed."
        case .otherLength(let gap): return String(format: "The closest runs %+.0fs from what is playing, too far to time the words by.", gap)
        case .notFound: return "Neither lyric source lists it. Nothing shows until the next song that has them."
        case .unreachable: return "Check this Mac's connection. Lyrik asks again by itself while the song plays."
        }
    }
}

/// What a style needs to draw one moment of the song.
struct LyricFrame {
    var time: Double
    var lines: [LyricLine]
    var index: Int?             // current line, nil before the first or with no lyrics
    var lineProgress: Double    // 0...1 through the sung part of the line
    var wordIndex: Int?         // current word within the line
    var wordProgress: Double    // 0...1 through the current word

    var current: LyricLine? { index.map { lines[$0] } }
    var previous: LyricLine? { index.flatMap { $0 > 0 ? lines[$0 - 1] : nil } }
    var next: LyricLine? {
        if let i = index { return i + 1 < lines.count ? lines[i + 1] : nil }
        return lines.first
    }

    /// Progress (0...1) of word `w` in the current line.
    func progress(ofWord w: Int) -> Double {
        guard let wi = wordIndex else { return 0 }
        if w < wi { return 1 }
        if w > wi { return 0 }
        return wordProgress
    }

    static let empty = LyricFrame(time: 0, lines: [], index: nil, lineProgress: 0, wordIndex: nil, wordProgress: 0)

    static func make(lines: [LyricLine], time t: Double) -> LyricFrame {
        guard !lines.isEmpty else { return LyricFrame(time: t, lines: [], index: nil, lineProgress: 0, wordIndex: nil, wordProgress: 0) }
        // Binary search for the last line starting at or before t.
        var lo = 0, hi = lines.count - 1, found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= t { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard found >= 0 else {
            return LyricFrame(time: t, lines: lines, index: nil, lineProgress: 0, wordIndex: nil, wordProgress: 0)
        }
        let line = lines[found]
        let sungEnd = line.words.last?.end ?? line.end
        let lp = sungEnd > line.start ? min(1, max(0, (t - line.start) / (sungEnd - line.start))) : 1
        var wi: Int?
        var wp = 0.0
        for (i, w) in line.words.enumerated() where w.start <= t {
            wi = i
            wp = w.end > w.start ? min(1, max(0, (t - w.start) / (w.end - w.start))) : 1
        }
        return LyricFrame(time: t, lines: lines, index: found, lineProgress: lp, wordIndex: wi, wordProgress: wp)
    }
}
