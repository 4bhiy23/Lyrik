import Foundation
import Combine

/// Fetches lyrics for whatever the monitor is following and maps the playhead onto them.
@MainActor
final class LyricEngine: ObservableObject {
    static let shared = LyricEngine()

    @Published private(set) var lyrics: TimedLyrics?
    @Published private(set) var status: LyricStatus = .idle
    /// Seconds the words are shifted for this song; positive shows them earlier.
    @Published private(set) var offset: Double = 0

    private let monitor = NowPlayingMonitor.shared
    private var songKey: String?
    private var fetchTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?

    func start() {
        cancellable = monitor.$sample
            .receive(on: RunLoop.main)
            .sink { [weak self] sample in self?.follow(sample) }
    }

    /// Lyric time for an uptime instant, including the per-song shift.
    func time(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        monitor.position(at: uptime) + offset
    }

    func frame(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> LyricFrame {
        guard let lyrics else { return .empty }
        return LyricFrame.make(lines: lyrics.lines, time: time(at: uptime))
    }

    // MARK: Song changes

    private func follow(_ sample: PlayerSample?) {
        guard let sample else {
            if songKey != nil {
                songKey = nil
                fetchTask?.cancel(); retryTask?.cancel()
                lyrics = nil
                status = .idle
            }
            return
        }
        guard sample.songKey != songKey else { return }
        songKey = sample.songKey
        offset = UserDefaults.standard.double(forKey: "offset." + sample.songKey)
        lyrics = nil
        fetch(sample)
    }

    private func fetch(_ sample: PlayerSample) {
        fetchTask?.cancel()
        retryTask?.cancel()
        let title = sample.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            status = .noTitle
            return
        }
        status = .looking
        let key = sample.songKey
        fetchTask = Task { [weak self] in
            let result = await LyricsProvider.shared.lookup(title: title, artist: sample.artist, album: sample.album, duration: sample.duration)
            guard !Task.isCancelled, let self, self.songKey == key else { return }
            self.apply(result, for: sample)
        }
    }

    private func apply(_ result: LyricLookup, for sample: PlayerSample) {
        switch result {
        case .found(let l):
            lyrics = l
            status = .found(source: l.source, wordLevel: l.wordLevel, gap: l.lengthGap)
            Log.write("lyrics: \(l.source), \(l.lines.count) lines, \(l.wordLevel ? "word" : "line") timing, gap \(String(format: "%+.1f", l.lengthGap))s")
        case .instrumental: status = .instrumental
        case .untimed: status = .untimed
        case .otherLength(let g): status = .otherLength(g)
        case .notFound: status = .notFound
        case .unreachable:
            status = .unreachable
            let key = sample.songKey
            retryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, let self, self.songKey == key else { return }
                self.fetch(sample)
            }
        }
        if case .found = status {} else { Log.write("lyrics: none for \(sample.artist) — \(sample.title): \(status.headline)") }
    }

    // MARK: User actions

    func shift(by delta: Double) {
        guard let key = songKey else { return }
        offset = (offset + delta).rounded(toPlaces: 1)
        UserDefaults.standard.set(offset, forKey: "offset." + key)
        Log.write("lyric timing for this song \(String(format: "%+.1fs", offset))")
    }

    func resetShift() {
        guard let key = songKey else { return }
        offset = 0
        UserDefaults.standard.removeObject(forKey: "offset." + key)
    }

    func lookAgain() {
        guard let sample = monitor.sample else { return }
        LyricsProvider.shared.clearCache(title: sample.title, artist: sample.artist, duration: sample.duration)
        Log.write("lyrics: looking again, asked from the panel")
        lyrics = nil
        fetch(sample)
    }
}

extension Double {
    func rounded(toPlaces p: Int) -> Double {
        let m = pow(10, Double(p))
        return (self * m).rounded() / m
    }
}
