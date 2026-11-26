import AppKit
import Carbon

/// Runs every Apple Event exchange with Spotify and Music on one serial queue.
/// NSAppleScript instances are compiled once and only ever touched from `queue`.
final class PlayerBridge: @unchecked Sendable {
    static let shared = PlayerBridge()

    let queue = DispatchQueue(label: "lyrik.player-bridge", qos: .userInitiated)
    private var readScripts: [PlayerKind: NSAppleScript] = [:]

    // MARK: Reading

    /// Reads one player. Never launches it: the script checks `is running` first.
    func read(_ player: PlayerKind) -> PlayerRead {
        dispatchPrecondition(condition: .onQueue(queue))
        guard player.isInstalled else { return .notInstalled }
        guard player.isRunning else { return .closed }

        guard let script = readScript(for: player) else {
            return .failed(-1, "the question could not be prepared")
        }
        var error: NSDictionary?
        let start = ProcessInfo.processInfo.systemUptime
        let result = script.executeAndReturnError(&error)
        let end = ProcessInfo.processInfo.systemUptime

        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? -1
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "unknown error"
            switch code {
            case -1743: return .denied
            case -1744: return .needsConsent
            case -600, -609: return .closed   // quit between the check and the event
            case -1712: return .failed(code, "did not answer in time")
            default: return .failed(code, message)
            }
        }
        return parse(result, player: player, sampledAt: (start + end) / 2)
    }

    private func readScript(for player: PlayerKind) -> NSAppleScript? {
        if let cached = readScripts[player] { return cached }
        let source = player == .spotify ? Self.spotifySource : Self.musicSource
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        if !script.compileAndReturnError(&error) {
            Log.write("players: compile failed for \(player.rawValue): \(error ?? [:])")
            return nil
        }
        readScripts[player] = script
        return script
    }

    private func parse(_ d: NSAppleEventDescriptor, player: PlayerKind, sampledAt: TimeInterval) -> PlayerRead {
        guard d.numberOfItems >= 1, let flagDesc = d.atIndex(1) else { return .failed(-2, "empty reply") }
        let flag = Int(flagDesc.int32Value)
        if flag == -1 { return .closed }
        if flag == 0 || d.numberOfItems < 9 { return .idle }

        func text(_ i: Int) -> String {
            let s = d.atIndex(i)?.stringValue ?? ""
            return s == "missing value" ? "" : s
        }
        func number(_ i: Int) -> Double? {
            guard let item = d.atIndex(i) else { return nil }
            let v = item.doubleValue
            return v < 0 ? nil : v
        }

        let artwork = text(8)
        let sample = PlayerSample(
            player: player,
            state: flag == 1 ? .playing : .paused,
            title: text(2),
            artist: text(3),
            album: text(4),
            duration: number(5) ?? 0,
            position: number(6),
            trackID: text(7),
            artworkURL: artwork.isEmpty ? nil : URL(string: artwork),
            volume: number(9).map { Int($0) },
            sampledAt: sampledAt
        )
        return .sample(sample)
    }

    // MARK: Artwork (Music hands over raw image bytes)

    func musicArtworkData() -> Data? {
        dispatchPrecondition(condition: .onQueue(queue))
        guard PlayerKind.music.isRunning else { return nil }
        let source = """
        if application id "com.apple.Music" is running then
            with timeout of 4 seconds
            tell application id "com.apple.Music"
                try
                    if (count of artworks of current track) > 0 then
                        return raw data of artwork 1 of current track
                    end if
                end try
            end tell
            end timeout
        end if
        return ""
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else { return nil }
        if result.descriptorType == typeUnicodeText || result.descriptorType == typeUTF8Text { return nil }
        let data = result.data
        return data.isEmpty ? nil : data
    }

    // MARK: Commands

    enum Command {
        case playPause, next, previous
        case seek(Double)
        case volume(Int)

        func statement(for player: PlayerKind) -> String {
            switch self {
            case .playPause: return "playpause"
            case .next: return "next track"
            case .previous: return "previous track"
            case .seek(let s): return String(format: "set player position to %.3f", max(0, s))
            case .volume(let v): return "set sound volume to \(min(100, max(0, v)))"
            }
        }
    }

    @discardableResult
    func send(_ command: Command, to player: PlayerKind) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard player.isRunning else { return false }
        let source = """
        if application id "\(player.bundleID)" is running then
            with timeout of 4 seconds
                tell application id "\(player.bundleID)" to \(command.statement(for: player))
            end timeout
        end if
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.write("players: \(player.rawValue) command failed: \(error[NSAppleScript.errorNumber] ?? "?")")
            return false
        }
        return true
    }

    // MARK: Scripts

    private static let spotifySource = """
    if application id "com.spotify.client" is running then
        with timeout of 4 seconds
        tell application id "com.spotify.client"
            set pState to player state
            if pState is stopped then return {0}
            set tName to ""
            set tArtist to ""
            set tAlbum to ""
            set tDur to -1
            set tPos to -1
            set tID to ""
            set tArt to ""
            set tVol to -1
            try
                set tName to (name of current track) as text
            end try
            try
                set tArtist to (artist of current track) as text
            end try
            try
                set tAlbum to (album of current track) as text
            end try
            try
                set tDur to ((duration of current track) as real) / 1000
            end try
            try
                set tPos to (player position) as real
            end try
            try
                set tID to (id of current track) as text
            end try
            try
                set tArt to (artwork url of current track) as text
            end try
            try
                set tVol to (sound volume) as integer
            end try
            if pState is playing then
                set flag to 1
            else
                set flag to 2
            end if
            return {flag, tName, tArtist, tAlbum, tDur, tPos, tID, tArt, tVol}
        end tell
        end timeout
    end if
    return {-1}
    """

    private static let musicSource = """
    if application id "com.apple.Music" is running then
        with timeout of 4 seconds
        tell application id "com.apple.Music"
            set pState to player state
            if pState is stopped then return {0}
            set tName to ""
            set tArtist to ""
            set tAlbum to ""
            set tDur to -1
            set tPos to -1
            set tID to ""
            set tVol to -1
            try
                set tName to (name of current track) as text
            end try
            if tName is "" then
                try
                    set tName to (current stream title) as text
                end try
            end if
            try
                set tArtist to (artist of current track) as text
            end try
            try
                set tAlbum to (album of current track) as text
            end try
            try
                set tDur to (duration of current track) as real
            end try
            try
                set tPos to (player position) as real
            end try
            try
                set tID to (persistent ID of current track) as text
            end try
            try
                set tVol to (sound volume) as integer
            end try
            if pState is playing then
                set flag to 1
            else
                set flag to 2
            end if
            return {flag, tName, tArtist, tAlbum, tDur, tPos, tID, "", tVol}
        end tell
        end timeout
    end if
    return {-1}
    """
}
