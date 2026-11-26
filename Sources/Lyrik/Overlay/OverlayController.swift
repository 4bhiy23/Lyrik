import AppKit
import SwiftUI
import Combine

/// A click-through, borderless window that covers one display.
final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the lyric windows for every display: one living above the lock screen,
/// one for the unlocked desktop. Shows each only when it should be seen.
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private struct DisplayWindows {
        var lock: OverlayWindow
        var desktop: OverlayWindow
    }

    private var windows: [CGDirectDisplayID: DisplayWindows] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let settings = AppSettings.shared
    private let lock = LockMonitor.shared
    private let monitor = NowPlayingMonitor.shared
    private let engine = LyricEngine.shared

    func start() {
        rebuild()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        Publishers.CombineLatest4(lock.$isLocked, settings.$showWhenUnlocked, settings.$lockScreen, engine.$lyrics.map { $0 != nil })
            .combineLatest(monitor.$sample.map { $0?.state == .playing }, settings.$unlockedPlacement, settings.$disabledDisplays)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)

        Publishers.CombineLatest(monitor.$sample.map { $0?.state == .playing }, settings.$keepAwake)
            .receive(on: RunLoop.main)
            .sink { playing, keep in ScreenAwake.shared.set(playing && keep) }
            .store(in: &cancellables)
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func displayKey(_ screen: NSScreen) -> String { screen.localizedName }

    private func rebuild() {
        let screens = NSScreen.screens
        let ids = Set(screens.map(Self.displayID))
        for (id, w) in windows where !ids.contains(id) {
            w.lock.orderOut(nil); w.desktop.orderOut(nil)
            windows[id] = nil
        }
        for screen in screens {
            let id = Self.displayID(screen)
            if let existing = windows[id] {
                existing.lock.setFrame(screen.frame, display: true)
                existing.desktop.setFrame(screen.frame, display: true)
                continue
            }
            let lockWindow = OverlayWindow(screen: screen)
            lockWindow.level = .screenSaver
            lockWindow.contentView = NSHostingView(rootView: OverlayRoot(mode: .lockScreen))
            lockWindow.alphaValue = 0
            lockWindow.orderFrontRegardless()
            SkyLightSpace.shared.adopt(lockWindow)

            let desktopWindow = OverlayWindow(screen: screen)
            desktopWindow.contentView = NSHostingView(rootView: OverlayRoot(mode: .desktop))
            desktopWindow.alphaValue = 0

            windows[id] = DisplayWindows(lock: lockWindow, desktop: desktopWindow)
            Log.write("overlay created for display \(id) (\(screen.localizedName))")
        }
        updateVisibility()
    }

    private func updateVisibility() {
        let hasLyrics = engine.lyrics != nil
        for screen in NSScreen.screens {
            guard let w = windows[Self.displayID(screen)] else { continue }
            let enabled = !settings.disabledDisplays.contains(Self.displayKey(screen))
            let showLock = enabled && settings.lockScreen && lock.isLocked && hasLyrics
            let showDesktop = enabled && settings.showWhenUnlocked && !lock.isLocked && hasLyrics

            fade(w.lock, visible: showLock)
            (w.lock.contentView as? NSHostingView<OverlayRoot>)?.rootView = OverlayRoot(mode: .lockScreen, active: showLock)

            w.desktop.level = settings.unlockedPlacement == .desktop
                ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
                : .floating
            if showDesktop { w.desktop.orderFrontRegardless() }
            let desktop = w.desktop
            fade(desktop, visible: showDesktop) {
                // Only order out if nothing asked for it again during the fade.
                MainActor.assumeIsolated { if desktop.alphaValue == 0 { desktop.orderOut(nil) } }
            }
            (w.desktop.contentView as? NSHostingView<OverlayRoot>)?.rootView = OverlayRoot(mode: .desktop, active: showDesktop)
        }
    }

    private func fade(_ window: NSWindow, visible: Bool, completion: (@Sendable () -> Void)? = nil) {
        let target: CGFloat = visible ? 1 : 0
        guard window.alphaValue != target else { completion?(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            window.animator().alphaValue = target
        }, completionHandler: completion)
    }
}

/// Root view of an overlay window; renders nothing (and costs nothing) while hidden.
struct OverlayRoot: View {
    var mode: LyricStageView.Mode
    var active = false

    var body: some View {
        ZStack {
            if active {
                LyricStageView(mode: mode)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
