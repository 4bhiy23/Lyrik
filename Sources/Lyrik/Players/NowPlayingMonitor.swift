import AppKit
import Combine

/// A linear playhead model: the reported position at a moment, extrapolated while playing.
struct PlayheadAnchor: Equatable {
    var position: Double
    var uptime: TimeInterval
    var playing: Bool
    var duration: Double

    func position(at now: TimeInterval) -> Double {
        let p = playing ? position + (now - uptime) : position
        return duration > 0 ? min(max(0, p), duration) : max(0, p)
    }
}

/// Follows whichever player is playing (Spotify if both are), and exposes its track,
/// a smooth playhead, artwork and transport controls.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    static let shared = NowPlayingMonitor()

    @Published private(set) var sample: PlayerSample?
    @Published private(set) var reads: [PlayerKind: PlayerRead] = [:]
    @Published private(set) var access: [PlayerKind: AutomationAccess] = [:]
    @Published private(set) var artwork: NSImage?
    @Published private(set) var palette: ArtworkPalette?
    @Published private(set) var anchor = PlayheadAnchor(position: 0, uptime: 0, playing: false, duration: 0)
    /// Set while the user drags the scrubber so polling does not fight the finger.
    @Published var scrubbing: Double?

    /// When false, a player macOS has not asked about yet is left alone
    /// (so a prompt never appears out of nowhere before onboarding).
    var mayAskForConsent = true

    private let bridge = PlayerBridge.shared
    private var timer: Timer?
    private var inFlight = false
    private var pendingPoll = false
    private var lastActive: PlayerKind?
    private var artworkKey: String?
    private var artworkTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastReadLog: [PlayerKind: String] = [:]

    var isPlaying: Bool { sample?.state == .playing }
    var activePlayer: PlayerKind? { sample?.player }

    func position(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        if let scrubbing { return scrubbing }
        return anchor.position(at: uptime)
    }

    // MARK: Lifecycle

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let dnc = DistributedNotificationCenter.default()
        for player in PlayerKind.allCases {
            observers.append(dnc.addObserver(forName: player.changeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            })
        }
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                guard PlayerKind.allCases.contains(where: { $0.bundleID == id }) else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self?.poll()
                }
            })
        }
        poll()
    }

    // MARK: Polling

    func poll() {
        if inFlight { pendingPoll = true; return }
        inFlight = true
        let knownAccess = access
        let othersPlaying = sample?.state == .playing ? sample?.player : nil
        let mayAsk = mayAskForConsent
        let everAllowed = Self.everAllowed
        let requested = consentRequested

        // Permission is learned from real reads: macOS answers -1743 when blocked,
        // and the first read of a player it has not asked about shows its prompt.
        // (AEDeterminePermissionToAutomateTarget can block indefinitely on some
        // targets, so it is never used.)
        bridge.queue.async { [bridge] in
            var reads: [PlayerKind: PlayerRead] = [:]
            var access: [PlayerKind: AutomationAccess] = [:]
            var newlyAllowed: [PlayerKind] = []
            for player in PlayerKind.allCases {
                guard player.isInstalled else { reads[player] = .notInstalled; access[player] = .unknown; continue }
                guard player.isRunning else { reads[player] = .closed; access[player] = knownAccess[player] ?? .unknown; continue }

                let known = everAllowed.contains(player.rawValue) || knownAccess[player] == .allowed || knownAccess[player] == .denied
                let wouldPrompt = !known && !requested.contains(player)
                // Never surprise the user with a prompt before onboarding, nor for a
                // second player while the first one is already playing.
                if wouldPrompt && (!mayAsk || (othersPlaying != nil && othersPlaying != player)) {
                    reads[player] = .needsConsent
                    access[player] = .notAsked
                    continue
                }
                let r = bridge.read(player)
                reads[player] = r
                switch r {
                case .sample, .idle:
                    access[player] = .allowed
                    if !everAllowed.contains(player.rawValue) { newlyAllowed.append(player) }
                case .denied: access[player] = .denied
                case .needsConsent: access[player] = .notAsked
                default: access[player] = knownAccess[player] ?? .unknown
                }
            }
            DispatchQueue.main.async {
                for p in newlyAllowed { Self.everAllowed.insert(p.rawValue) }
                self.apply(reads: reads, access: access)
                self.inFlight = false
                if self.pendingPoll {
                    self.pendingPoll = false
                    self.poll()
                }
            }
        }
    }

    private func apply(reads newReads: [PlayerKind: PlayerRead], access newAccess: [PlayerKind: AutomationAccess]) {
        for (player, read) in newReads {
            let summary = Self.describe(read)
            if lastReadLog[player] != summary {
                lastReadLog[player] = summary
                Log.write("players: \(player.rawValue) \(summary)")
            }
        }
        if newReads != reads { reads = newReads }
        if newAccess != access { access = newAccess }

        let samples = PlayerKind.allCases.compactMap { newReads[$0]?.sample }
        let playing = samples.filter { $0.state == .playing }
        let chosen: PlayerSample?
        if let s = playing.first(where: { $0.player == .spotify }) ?? playing.first {
            chosen = s
        } else if let last = lastActive, let s = samples.first(where: { $0.player == last }) {
            chosen = s
        } else {
            chosen = samples.first
        }

        guard let chosen else {
            if sample != nil {
                Log.write("now playing: nothing playing in Spotify or Music")
                sample = nil
                anchor = PlayheadAnchor(position: 0, uptime: ProcessInfo.processInfo.systemUptime, playing: false, duration: 0)
                setArtwork(nil, key: nil)
            }
            return
        }

        let trackChanged = sample?.songKey != chosen.songKey
        if trackChanged {
            Log.write(String(format: "now playing (%@): %@ — %@ (%.1fs) at %.1fs",
                             chosen.player.rawValue, chosen.artist, chosen.title, chosen.duration, chosen.position ?? -1))
        }
        lastActive = chosen.player
        updateAnchor(with: chosen, trackChanged: trackChanged)
        if sample != chosen { sample = chosen }
        if trackChanged || artworkKey != chosen.songKey { loadArtwork(for: chosen) }
    }

    private func updateAnchor(with s: PlayerSample, trackChanged: Bool) {
        guard let reported = s.position else {
            anchor = PlayheadAnchor(position: 0, uptime: s.sampledAt, playing: false, duration: s.duration)
            return
        }
        let playing = s.state == .playing
        let fresh = PlayheadAnchor(position: reported, uptime: s.sampledAt, playing: playing, duration: s.duration)
        // Keep the running anchor when it agrees closely: re-anchoring every poll
        // would make word timing twitch by the event round-trip jitter.
        if !trackChanged, anchor.playing, playing, abs(anchor.position(at: s.sampledAt) - reported) < 0.3 {
            if anchor.duration != s.duration { anchor.duration = s.duration }
            return
        }
        anchor = fresh
    }

    static func describe(_ read: PlayerRead) -> String {
        switch read {
        case .notInstalled: return "not installed"
        case .closed: return "closed"
        case .idle: return "read fine, nothing playing in it"
        case .denied: return "blocked in System Settings"
        case .needsConsent: return "needs your permission"
        case .failed(let code, let msg): return "failed (\(code)): \(msg)"
        case .sample(let s):
            let state = s.state == .playing ? "playing" : "paused"
            return s.title.isEmpty ? "read fine, \(state), no title given" : "read fine, \(state)"
        }
    }

    // MARK: Artwork

    private func loadArtwork(for s: PlayerSample, attempt: Int = 0) {
        artworkKey = s.songKey
        artworkTask?.cancel()
        let key = s.songKey
        if let cached = ArtworkCache.shared.image(for: key) {
            setArtwork(cached, key: key)
            return
        }
        artworkTask = Task { [weak self] in
            var image: NSImage?
            switch s.player {
            case .spotify:
                if let url = s.artworkURL {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 10
                    if let (data, _) = try? await URLSession.shared.data(for: request) { image = NSImage(data: data) }
                }
            case .music:
                // Music may not have the artwork ready the instant the track flips.
                for attempt in 0..<3 {
                    let data: Data? = await withCheckedContinuation { cont in
                        PlayerBridge.shared.queue.async { cont.resume(returning: PlayerBridge.shared.musicArtworkData()) }
                    }
                    if let data, let img = NSImage(data: data) { image = img; break }
                    if Task.isCancelled { return }
                    try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
                }
            }
            if Task.isCancelled { return }
            guard let self, self.artworkKey == key else { return }
            if let image {
                ArtworkCache.shared.store(image, for: key)
                self.setArtwork(image, key: key)
            } else {
                Log.write("artwork: none for current track (attempt \(attempt + 1))")
                self.setArtwork(nil, key: key)
                // Networks drop out; try again a couple of times while the song lasts.
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 12_000_000_000)
                    guard !Task.isCancelled, self.artworkKey == key, let current = self.sample, current.songKey == key else { return }
                    self.loadArtwork(for: current, attempt: attempt + 1)
                }
            }
        }
    }

    private func setArtwork(_ image: NSImage?, key: String?) {
        artwork = image
        if let image {
            let p = ArtworkPalette.extract(from: image)
            palette = p
            if p == nil { Log.write("artwork: palette extraction failed") }
        } else {
            palette = nil
        }
    }

    // MARK: Controls

    func playPause() {
        guard let player = activePlayer ?? PlayerKind.allCases.first(where: { $0.isRunning }) else { return }
        // Answer the click at once; the next poll confirms.
        let now = ProcessInfo.processInfo.systemUptime
        let pos = anchor.position(at: now)
        anchor = PlayheadAnchor(position: pos, uptime: now, playing: !anchor.playing, duration: anchor.duration)
        if var s = sample {
            s.state = anchor.playing ? .playing : .paused
            sample = s
        }
        run(.playPause, on: player)
    }

    func next() {
        guard let player = activePlayer else { return }
        run(.next, on: player)
    }

    func previous() {
        guard let player = activePlayer else { return }
        run(.previous, on: player)
    }

    func seek(to seconds: Double) {
        guard let player = activePlayer else { return }
        let now = ProcessInfo.processInfo.systemUptime
        anchor = PlayheadAnchor(position: seconds, uptime: now, playing: anchor.playing, duration: anchor.duration)
        run(.seek(seconds), on: player)
    }

    func setVolume(_ volume: Int) {
        guard let player = activePlayer else { return }
        if var s = sample { s.volume = volume; sample = s }
        run(.volume(volume), on: player, pollAfter: false)
    }

    private func run(_ command: PlayerBridge.Command, on player: PlayerKind, pollAfter: Bool = true) {
        bridge.queue.async { [bridge] in
            bridge.send(command, to: player)
            guard pollAfter else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.poll() }
        }
    }

    /// Players the user explicitly asked to connect; reading them may show macOS's prompt.
    private var consentRequested: Set<PlayerKind> = []

    /// Players that have answered at least once, remembered across launches.
    static var everAllowed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "players.allowed") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "players.allowed") }
    }

    /// Reads `player` now, which makes macOS show its consent prompt if it has not asked yet.
    func requestAccess(_ player: PlayerKind) {
        mayAskForConsent = true
        consentRequested.insert(player)
        access[player] = nil
        Log.write("players: asking about \(player.rawValue)")
        poll()
    }

    /// After `tccutil reset`, forget what macOS had answered.
    func forgetAccess() {
        Self.everAllowed = []
        access = [:]
    }
}

/// Small in-memory artwork cache keyed by song.
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.countLimit = 24 }
    func image(for key: String) -> NSImage? { cache.object(forKey: key as NSString) }
    func store(_ image: NSImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}
