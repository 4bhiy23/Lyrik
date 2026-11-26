import AppKit

/// The two desktop players Lyrik talks to over Apple Events.
enum PlayerKind: String, CaseIterable, Identifiable, Codable {
    case spotify
    case music

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Apple Music"
        }
    }

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var isInstalled: Bool { appURL != nil }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    var icon: NSImage? {
        guard let url = appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Distributed notification each player posts when its state or track changes.
    var changeNotification: Notification.Name {
        switch self {
        case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .music: return Notification.Name("com.apple.Music.playerInfo")
        }
    }
}

enum PlaybackState: Equatable {
    case playing, paused, stopped
}

/// One reading of a player, taken at `sampledAt` (monotonic uptime seconds).
struct PlayerSample: Equatable {
    var player: PlayerKind
    var state: PlaybackState
    var title: String
    var artist: String
    var album: String
    var duration: Double      // seconds, 0 when unknown
    var position: Double?     // seconds
    var trackID: String
    var artworkURL: URL?
    var volume: Int?
    var sampledAt: TimeInterval

    /// Stable identity of the song for caches and per-song settings.
    var songKey: String {
        if !trackID.isEmpty { return "\(player.rawValue):\(trackID)" }
        return "\(player.rawValue):\(artist)|\(title)|\(Int(duration.rounded()))"
    }
}

/// Outcome of asking one player what it is doing.
enum PlayerRead: Equatable {
    case notInstalled
    case closed
    case idle                       // open, nothing loaded
    case sample(PlayerSample)
    case denied                     // -1743, blocked in System Settings
    case needsConsent               // -1744, not asked yet
    case failed(Int, String)

    var sample: PlayerSample? {
        if case .sample(let s) = self { return s }
        return nil
    }
}

/// Automation permission for one player, as macOS reports it.
enum AutomationAccess: Equatable {
    case unknown        // player closed, cannot be checked
    case allowed
    case denied
    case notAsked
}
