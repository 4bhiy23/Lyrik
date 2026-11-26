import Foundation

enum LyricParsers {
    // MARK: LRC (line-synced, optionally with <mm:ss.xx> word tags)

    private static let timeTag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)>"#)
    private static let offsetTag = try! NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\]"#, options: .caseInsensitive)

    static func seconds(_ minutes: String, _ rest: String) -> Double {
        let m = Double(minutes) ?? 0
        let s = Double(rest.replacingOccurrences(of: ":", with: ".")) ?? 0
        return m * 60 + s
    }

    static func parseLRC(_ text: String, duration: Double) -> (lines: [LyricLine], wordLevel: Bool) {
        var offset = 0.0
        let ns = text as NSString
        if let m = offsetTag.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            offset = (Double(ns.substring(with: m.range(at: 1))) ?? 0) / 1000
        }

        struct Raw { var start: Double; var body: String }
        var raws: [Raw] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            let matches = timeTag.matches(in: rawLine, range: NSRange(location: 0, length: line.length))
            guard !matches.isEmpty else { continue }
            // Timestamps sit at the front; several may share one body.
            var cursor = 0
            var stamps: [Double] = []
            for m in matches where m.range.location == cursor {
                stamps.append(seconds(line.substring(with: m.range(at: 1)), line.substring(with: m.range(at: 2))))
                cursor = m.range.location + m.range.length
            }
            guard !stamps.isEmpty else { continue }
            let body = line.substring(from: cursor)
            for s in stamps { raws.append(Raw(start: max(0, s - offset), body: body)) }
        }
        raws.sort { $0.start < $1.start }

        var wordLevel = false
        var lines: [LyricLine] = []
        for (i, raw) in raws.enumerated() {
            let nextStart = i + 1 < raws.count ? raws[i + 1].start : (duration > raw.start ? duration : raw.start + 6)
            var words: [TimedWord] = []
            let bodyNS = raw.body as NSString
            let tags = wordTag.matches(in: raw.body, range: NSRange(location: 0, length: bodyNS.length))
            var plain = raw.body
            if !tags.isEmpty {
                // Enhanced LRC: "<00:01.20> word <00:01.70> word"
                var stamps: [(Double, NSRange)] = tags.map {
                    (seconds(bodyNS.substring(with: $0.range(at: 1)), bodyNS.substring(with: $0.range(at: 2))) - offset, $0.range)
                }
                stamps.sort { $0.1.location < $1.1.location }
                for (k, stamp) in stamps.enumerated() {
                    let from = stamp.1.location + stamp.1.length
                    let to = k + 1 < stamps.count ? stamps[k + 1].1.location : bodyNS.length
                    guard to > from else { continue }
                    let chunk = bodyNS.substring(with: NSRange(location: from, length: to - from))
                    guard !chunk.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    let end = k + 1 < stamps.count ? stamps[k + 1].0 : min(nextStart, stamp.0 + 1.2)
                    words.append(TimedWord(start: stamp.0, end: max(end, stamp.0 + 0.05), text: chunk.hasSuffix(" ") ? chunk : chunk + " "))
                }
                plain = wordTag.stringByReplacingMatches(in: raw.body, range: NSRange(location: 0, length: bodyNS.length), withTemplate: "")
                    .replacingOccurrences(of: "  ", with: " ")
                if !words.isEmpty { wordLevel = true }
            }
            let trimmed = plain.trimmingCharacters(in: .whitespaces)
            if words.isEmpty, !trimmed.isEmpty {
                words = interpolate(trimmed, start: raw.start, limit: nextStart)
            }
            if !words.isEmpty {
                words[words.count - 1].text = words[words.count - 1].text.trimmingCharacters(in: .whitespaces)
            }
            lines.append(LyricLine(id: lines.count, start: raw.start, end: nextStart, text: trimmed, words: words))
        }
        return (dropLeadingCredits(lines), wordLevel)
    }

    // MARK: NetEase YRC: "[start,dur](ws,wd,0)word(ws,wd,0)word"

    private static let yrcLine = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\](.*)$"#)
    private static let yrcWord = try! NSRegularExpression(pattern: #"\((\d+),(\d+),-?\d+\)"#)

    static func parseYRC(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let s = raw.trimmingCharacters(in: .whitespaces)
            guard !s.hasPrefix("{"), let m = yrcLine.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { continue }
            let ns = s as NSString
            let start = (Double(ns.substring(with: m.range(at: 1))) ?? 0) / 1000
            let dur = (Double(ns.substring(with: m.range(at: 2))) ?? 0) / 1000
            let body = ns.substring(with: m.range(at: 3)) as NSString
            let tags = yrcWord.matches(in: body as String, range: NSRange(location: 0, length: body.length))
            var words: [TimedWord] = []
            for (k, t) in tags.enumerated() {
                let ws = (Double(body.substring(with: t.range(at: 1))) ?? 0) / 1000
                let wd = (Double(body.substring(with: t.range(at: 2))) ?? 0) / 1000
                let from = t.range.location + t.range.length
                let to = k + 1 < tags.count ? tags[k + 1].range.location : body.length
                guard to > from else { continue }
                let chunk = body.substring(with: NSRange(location: from, length: to - from))
                guard !chunk.isEmpty else { continue }
                words.append(TimedWord(start: ws, end: ws + max(wd, 0.05), text: chunk))
            }
            words = tidyWordChunks(words)
            let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            lines.append(LyricLine(id: 0, start: start, end: start + dur, text: text, words: words))
        }
        lines.sort { $0.start < $1.start }
        // Extend each line to the next one's start, and insert breaks across long silences.
        var out: [LyricLine] = []
        for (i, var line) in lines.enumerated() {
            let sungEnd = line.end
            let nextStart = i + 1 < lines.count ? lines[i + 1].start : line.end + 4
            line.end = max(line.end, nextStart)
            line.id = out.count
            out.append(line)
            if nextStart - sungEnd > 6 {
                out.append(LyricLine(id: out.count, start: sungEnd + 1.5, end: nextStart, text: "", words: []))
                out[out.count - 2].end = sungEnd + 1.5
            }
        }
        return dropLeadingCredits(out)
    }

    // MARK: Helpers

    /// Spreads a line's words over the time it is likely sung, weighted by length.
    static func interpolate(_ text: String, start: Double, limit: Double) -> [TimedWord] {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return [] }
        let chars = tokens.reduce(0) { $0 + $1.count }
        let natural = 0.075 * Double(chars) + 0.18 * Double(tokens.count) + 0.4
        let span = max(0.4, min(limit - start - 0.05, natural))
        let weights = tokens.map { Double($0.trimmingCharacters(in: .whitespaces).count) + 1.5 }
        let total = weights.reduce(0, +)
        var t = start
        return zip(tokens, weights).map { token, w in
            let d = span * w / total
            defer { t += d }
            return TimedWord(start: t, end: t + d, text: token)
        }
    }

    /// Splits on spaces (keeping them); CJK text without spaces becomes one token per character.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in text {
            if ch == " " {
                if !current.isEmpty { tokens.append(current + " "); current = "" }
            } else if ch.unicodeScalars.contains(where: { isCJK($0) }) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF: return true
        default: return false
        }
    }

    /// Word-timed sources sometimes split "how" / "to" without the space between,
    /// and give punctuation its own chunk. Restore spaces and fold punctuation into
    /// the word before it.
    static func tidyWordChunks(_ words: [TimedWord]) -> [TimedWord] {
        var out: [TimedWord] = []
        for w in words {
            let trimmed = w.text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isPunctuation }), var last = out.popLast() {
                let trailing = w.text.hasSuffix(" ") ? " " : ""
                last.text = last.text.trimmingCharacters(in: .whitespaces) + trimmed + trailing
                last.end = max(last.end, w.end)
                out.append(last)
                continue
            }
            if var last = out.popLast() {
                let joins = last.text.last.map { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" } ?? false
                let starts = w.text.first.map { $0.isLetter || $0.isNumber } ?? false
                let latin = last.text.unicodeScalars.allSatisfy { !isCJK($0) } && w.text.unicodeScalars.allSatisfy { !isCJK($0) }
                if joins && starts && latin { last.text += " " }
                out.append(last)
            }
            out.append(w)
        }
        return out
    }

    private static let creditLine = try! NSRegularExpression(pattern: #"^\s*[^:：]{1,24}?\s*[:：]\s*\S"#)

    /// Sources often open with "Artist: …", "作词 : …" credit lines; they are not sung.
    private static func dropLeadingCredits(_ lines: [LyricLine]) -> [LyricLine] {
        let markers = ["作词", "作曲", "编曲", "制作人", "Lyrics by", "Composed by", "Written by", "Producer", "词", "曲"]
        var out = lines
        while let first = out.first, first.start < 25 {
            let t = first.text
            let isCredit = markers.contains(where: { t.hasPrefix($0) })
                || (creditLine.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil && t.count < 60)
            guard isCredit else { break }
            out.removeFirst()
        }
        return out.enumerated().map { var l = $1; l.id = $0; return l }
    }
}
