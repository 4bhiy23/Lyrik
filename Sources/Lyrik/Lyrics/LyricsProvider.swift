import Foundation
import CryptoKit

/// Result of one lookup, before it reaches the UI.
enum LyricLookup {
    case found(TimedLyrics)
    case instrumental
    case untimed
    case otherLength(Double)
    case notFound
    case unreachable
}

/// Finds timed lyrics on LRCLIB, with NetEase Cloud Music for word-level timing and as a fallback.
final class LyricsProvider {
    static let shared = LyricsProvider()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()
    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("local.cadence.lyrics/v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private let userAgent = "Lyrik/1.0 (macOS lyrics overlay)"
    private let browserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Seconds a source's version may differ from what is playing and still be used.
    static let acceptGap = 3.0
    /// Beyond this the timing is too far off to trust at all.
    static let rejectGap = 12.0

    // MARK: Public

    func lookup(title: String, artist: String, album: String, duration: Double) async -> LyricLookup {
        let key = cacheKey(title: title, artist: artist, duration: duration)
        if let cached = readCache(key) {
            Log.write("lyrics: cache hit (\(artist) — \(title))")
            return cached
        }

        var anyAnswered = false
        var anySilent = false
        var best: TimedLyrics?
        var sawInstrumental = false
        var sawUntimed = false
        var closestGap: Double?

        // Ask both sources at once; LRCLIB (exact signature, then search) is preferred
        // unless NetEase has word-level timing for the same version.
        async let lrclibAnswer = lrclib(title: title, artist: artist, album: album, duration: duration)
        async let neteaseAnswer = netease(title: title, artist: artist, duration: duration)

        switch await lrclibAnswer {
        case .answered(let outcome):
            anyAnswered = true
            switch outcome {
            case .lyrics(let l): best = l
            case .instrumental: sawInstrumental = true
            case .untimed: sawUntimed = true
            case .gap(let g): closestGap = g
            case .none: break
            }
        case .unreachable: anySilent = true
        }

        // NetEase: word-level timing beats line-level, and it covers many songs LRCLIB lacks.
        let ne = await neteaseAnswer
        if best?.wordLevel != true, !sawInstrumental {
            switch ne {
            case .answered(let outcome):
                anyAnswered = true
                switch outcome {
                case .lyrics(let l):
                    if l.wordLevel || best == nil { best = l }
                case .gap(let g):
                    if closestGap == nil || abs(g) < abs(closestGap!) { closestGap = g }
                case .untimed: sawUntimed = true
                default: break
                }
            case .unreachable: anySilent = true
            }
        }

        let result: LyricLookup
        if let best { result = .found(best) }
        else if sawInstrumental { result = .instrumental }
        // A miss only counts when every source answered; otherwise ask again later.
        else if anySilent { result = .unreachable }
        else if let g = closestGap { result = .otherLength(g) }
        else if sawUntimed { result = .untimed }
        else if anyAnswered { result = .notFound }
        else { result = .unreachable }

        if case .unreachable = result {
            Log.write(anyAnswered ? "lyrics: nothing yet; a source did not answer" : "lyrics: lyric sources did not answer")
        } else {
            writeCache(key, result)
        }
        return result
    }

    // MARK: Title cleanup

    private static let cleanups: [NSRegularExpression] = [
        #"\s*[\(\[](feat|ft|with|featuring)[.\s][^\)\]]*[\)\]]"#,
        #"\s*[\(\[](from|theme from|music from)\s[^\)\]]*[\)\]]"#,
        #"\s*[\(\[](\d{4}\s)?(re-?master(ed)?|deluxe|bonus|explicit|single|album|radio|mono|stereo)[^\)\]]*[\)\]]"#,
        #"\s+-\s+.*(remaster(ed)?|version|edit|mix|acoustic|live|instrumental|mono|stereo).*$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    static func clean(_ title: String) -> String {
        var t = title
        for re in cleanups {
            t = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    /// The first credited artist, without "feat." tails.
    static func primaryArtist(_ artist: String) -> String {
        let separators = [", ", " & ", " feat. ", " ft. ", " featuring ", " x ", " X ", "、", " and "]
        var a = artist
        for sep in separators {
            if let r = a.range(of: sep) { a = String(a[..<r.lowerBound]) }
        }
        return a.trimmingCharacters(in: .whitespaces)
    }

    // MARK: LRCLIB

    private enum Outcome {
        case lyrics(TimedLyrics), instrumental, untimed, gap(Double), none
    }
    private enum SourceAnswer {
        case answered(Outcome), unreachable
    }

    private struct LrclibRecord: Decodable {
        var id: Int?
        var trackName: String?
        var artistName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    private func lrclib(title: String, artist: String, album: String, duration: Double) async -> SourceAnswer {
        // Exact signature lookup.
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if !album.isEmpty { comps.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { comps.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }

        var reachable = false
        guard let (data, status) = await get(comps.url!, agent: userAgent) else { return .unreachable }
        do {
            reachable = true
            if status == 200, let record = try? JSONDecoder().decode(LrclibRecord.self, from: data) {
                if record.instrumental == true { return .answered(.instrumental) }
                if let synced = record.syncedLyrics, !synced.isEmpty,
                   let lyrics = build(lrc: synced, source: "lrclib", sourceDuration: record.duration ?? duration, playing: duration) {
                    return .answered(.lyrics(lyrics))
                }
            }
        }

        // Search: raw title, then cleaned title, with the primary artist.
        var candidates: [LrclibRecord] = []
        var queries = [(title, artist)]
        let cleaned = Self.clean(title)
        let primary = Self.primaryArtist(artist)
        if cleaned != title || primary != artist { queries.append((cleaned, primary)) }
        for (t, a) in queries {
            var s = URLComponents(string: "https://lrclib.net/api/search")!
            s.queryItems = [URLQueryItem(name: "track_name", value: t), URLQueryItem(name: "artist_name", value: a)]
            guard let (data, status) = await get(s.url!, agent: userAgent) else { continue }
            reachable = true
            if status == 200, let list = try? JSONDecoder().decode([LrclibRecord].self, from: data) {
                candidates += list
            }
            if candidates.contains(where: { ($0.syncedLyrics?.isEmpty == false) && abs(($0.duration ?? 0) - duration) <= Self.acceptGap }) { break }
        }
        guard reachable else { return .unreachable }

        let wantTitle = Self.fold(cleaned)
        let relevant = candidates.filter {
            let t = Self.fold(Self.clean($0.trackName ?? ""))
            return !t.isEmpty && (t == wantTitle || t.contains(wantTitle) || wantTitle.contains(t))
        }
        let synced = relevant.filter { $0.syncedLyrics?.isEmpty == false }
        if let pick = synced.min(by: { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }) {
            let gap = (pick.duration ?? duration) - duration
            if duration <= 0 || abs(gap) <= Self.rejectGap,
               let lyrics = build(lrc: pick.syncedLyrics!, source: "lrclib", sourceDuration: pick.duration ?? duration, playing: duration) {
                return .answered(.lyrics(lyrics))
            }
            return .answered(.gap(gap))
        }
        if relevant.contains(where: { $0.instrumental == true }) { return .answered(.instrumental) }
        if relevant.contains(where: { $0.plainLyrics?.isEmpty == false }) { return .answered(.untimed) }
        return .answered(.none)
    }

    private func build(lrc: String, source: String, sourceDuration: Double, playing: Double) -> TimedLyrics? {
        let parsed = LyricParsers.parseLRC(lrc, duration: playing > 0 ? playing : sourceDuration)
        guard parsed.lines.contains(where: { !$0.isBreak }) else { return nil }
        return TimedLyrics(lines: parsed.lines, source: source, wordLevel: parsed.wordLevel,
                           lengthGap: playing > 0 ? sourceDuration - playing : 0)
    }

    // MARK: NetEase

    private struct NeteaseSearch: Decodable {
        struct Result: Decodable { var songs: [Song]? }
        struct Song: Decodable {
            var id: Int
            var name: String
            var duration: Double?
            var artists: [Artist]?
        }
        struct Artist: Decodable { var name: String }
        var code: Int?
        var result: Result?
    }

    private struct NeteaseLyric: Decodable {
        struct Body: Decodable { var lyric: String? }
        var lrc: Body?
        var yrc: Body?
        var nolyric: Bool?
        var uncollected: Bool?
    }

    private func netease(title: String, artist: String, duration: Double) async -> SourceAnswer {
        let cleaned = Self.clean(title)
        let primary = Self.primaryArtist(artist)
        var comps = URLComponents(string: "https://music.163.com/api/search/get")!
        comps.queryItems = [
            URLQueryItem(name: "s", value: "\(cleaned) \(primary)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "12"),
            URLQueryItem(name: "offset", value: "0"),
        ]
        guard let (data, status) = await get(comps.url!, agent: browserAgent, referer: "https://music.163.com/") else { return .unreachable }
        guard status == 200, let search = try? JSONDecoder().decode(NeteaseSearch.self, from: data) else { return .answered(.none) }
        if let code = search.code, code != 200 {
            Log.write("lyrics: ncm search refused (code \(code))")
            return .answered(.none)
        }

        let wantTitle = Self.fold(cleaned)
        let wantArtists = Set(artist.components(separatedBy: CharacterSet(charactersIn: ",&/、")).map { Self.fold($0) }.filter { !$0.isEmpty } + [Self.fold(primary)])
        let songs = (search.result?.songs ?? []).filter { song in
            let t = Self.fold(Self.clean(song.name))
            guard !t.isEmpty, t == wantTitle || t.hasPrefix(wantTitle) || wantTitle.hasPrefix(t) else { return false }
            let names = (song.artists ?? []).map { Self.fold($0.name) }
            return names.contains { n in wantArtists.contains { $0 == n || $0.contains(n) || n.contains($0) } }
        }
        guard !songs.isEmpty else { return .answered(.none) }

        let ranked = songs.sorted { abs(($0.duration ?? 0) / 1000 - duration) < abs(($1.duration ?? 0) / 1000 - duration) }
        let pick = ranked[0]
        let gap = (pick.duration ?? 0) / 1000 - duration
        if duration > 0, abs(gap) > Self.rejectGap { return .answered(.gap(gap)) }

        var lyricURL = URLComponents(string: "https://music.163.com/api/song/lyric/v1")!
        lyricURL.queryItems = [
            URLQueryItem(name: "id", value: String(pick.id)),
            URLQueryItem(name: "lv", value: "-1"), URLQueryItem(name: "yv", value: "-1"),
            URLQueryItem(name: "tv", value: "0"), URLQueryItem(name: "rv", value: "0"),
        ]
        guard let (ldata, lstatus) = await get(lyricURL.url!, agent: browserAgent, referer: "https://music.163.com/") else { return .unreachable }
        guard lstatus == 200, let body = try? JSONDecoder().decode(NeteaseLyric.self, from: ldata) else { return .answered(.none) }
        if body.nolyric == true { return .answered(.none) }

        let sourceDuration = (pick.duration ?? duration * 1000) / 1000
        if let yrc = body.yrc?.lyric, !yrc.isEmpty {
            let lines = LyricParsers.parseYRC(yrc)
            if lines.contains(where: { !$0.isBreak }) {
                return .answered(.lyrics(TimedLyrics(lines: lines, source: "netease", wordLevel: true, lengthGap: gap)))
            }
        }
        if let lrc = body.lrc?.lyric, !lrc.isEmpty {
            if let built = build(lrc: lrc, source: "netease", sourceDuration: sourceDuration, playing: duration) {
                return .answered(.lyrics(built))
            }
            return .answered(.untimed)
        }
        return .answered(.none)
    }

    // MARK: Networking

    private func get(_ url: URL, agent: String, referer: String? = nil) async -> (Data, Int)? {
        var request = URLRequest(url: url)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status >= 500 { Log.write("lyrics: \(url.host ?? "?") answered \(status)") }
            return (data, status)
        } catch {
            Log.write("lyrics: request to \(url.host ?? "?") failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Cache

    private struct CacheEntry: Codable {
        var kind: String
        var lyrics: TimedLyrics?
        var gap: Double?
        var savedAt: Date
    }

    private func cacheKey(title: String, artist: String, duration: Double) -> String {
        let raw = "\(Self.fold(artist))|\(Self.fold(title))|\(Int(duration.rounded()))"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func readCache(_ key: String) -> LyricLookup? {
        let url = cacheDir.appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: url), let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else { return nil }
        // Misses are retried after a day; found lyrics are kept.
        if entry.kind != "found", Date().timeIntervalSince(entry.savedAt) > 86_400 { return nil }
        switch entry.kind {
        case "found": return entry.lyrics.map { .found($0) }
        case "instrumental": return .instrumental
        case "untimed": return .untimed
        case "gap": return .otherLength(entry.gap ?? 0)
        case "none": return .notFound
        default: return nil
        }
    }

    private func writeCache(_ key: String, _ result: LyricLookup) {
        var entry = CacheEntry(kind: "none", lyrics: nil, gap: nil, savedAt: Date())
        switch result {
        case .found(let l): entry.kind = "found"; entry.lyrics = l
        case .instrumental: entry.kind = "instrumental"
        case .untimed: entry.kind = "untimed"
        case .otherLength(let g): entry.kind = "gap"; entry.gap = g
        case .notFound: entry.kind = "none"
        case .unreachable: return
        }
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: cacheDir.appendingPathComponent(key + ".json"), options: .atomic)
        }
    }

    func clearCache(title: String, artist: String, duration: Double) {
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(cacheKey(title: title, artist: artist, duration: duration) + ".json"))
    }
}
