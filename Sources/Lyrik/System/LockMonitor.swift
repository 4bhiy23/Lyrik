import AppKit
import CoreGraphics

/// Tracks whether the login window is covering the session.
@MainActor
final class LockMonitor: ObservableObject {
    static let shared = LockMonitor()

    @Published private(set) var isLocked: Bool = LockMonitor.querySession()
    private var observers: [NSObjectProtocol] = []

    func start() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.set(true) }
        })
        observers.append(dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.set(false) }
        })
        // Waking from sleep can skip a notification; ask the session directly.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.set(LockMonitor.querySession()) }
        })
    }

    private func set(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        Log.write(locked ? "screen locked" : "screen unlocked")
    }

    nonisolated static func querySession() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? ((dict["CGSSessionScreenIsLocked"] as? Int) == 1)
    }
}
