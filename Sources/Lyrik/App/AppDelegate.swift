import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var gallery: GalleryWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if exitIfAlreadyRunning() { return }
        Log.write("Lyrik \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") started")

        let settings = AppSettings.shared
        let monitor = NowPlayingMonitor.shared
        monitor.mayAskForConsent = settings.onboardingDone
        monitor.start()
        LyricEngine.shared.start()
        LockMonitor.shared.start()
        OverlayController.shared.start()
        WordVisualResolver.shared.preload()

        setUpStatusItem()

        let args = CommandLine.arguments
        if !settings.onboardingDone || args.contains("--open-window") || args.contains("--snapshot") {
            showGallery()
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                Snapshots.run(into: dir, gallery: self?.gallery?.window)
            }
        }
        installDebugHooksIfEnabled()
    }

    /// Developer testing only, off unless `defaults write local.cadence.lyrics debugHooks -bool true`:
    /// lets a local script drive the transport and request snapshots/state dumps.
    private func installDebugHooksIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "debugHooks") else { return }
        Log.write("debug hooks enabled")
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.cadence.debug"), object: nil, queue: .main) { [weak self] note in
            let command = note.object as? String ?? ""
            Task { @MainActor in self?.handleDebug(command) }
        }
    }

    private func handleDebug(_ command: String) {
        let monitor = NowPlayingMonitor.shared
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        switch parts.first ?? "" {
        case "playpause": monitor.playPause()
        case "next": monitor.next()
        case "previous": monitor.previous()
        case "seek": monitor.seek(to: Double(parts.count > 1 ? parts[1] : "0") ?? 0)
        case "style": if parts.count > 1, let s = LyricStyle(rawValue: parts[1]) { AppSettings.shared.style = s }
        case "unlocked": AppSettings.shared.showWhenUnlocked = parts.count > 1 && parts[1] == "on"
        case "present": PresentWindowController.shared.present()
        case "present-snapshot":
            if parts.count > 1, let view = PresentWindowController.shared.window?.contentView {
                Snapshots.save(view, to: URL(fileURLWithPath: parts[1]))
            }
        case "snapshot": if parts.count > 1 { showGallery(); Snapshots.run(into: URL(fileURLWithPath: parts[1]), gallery: gallery?.window) }
        case "state":
            let s = monitor.sample
            let f = LyricEngine.shared.frame()
            Log.write(String(format: "state: %@ %@ — %@ pos=%.2f/%.1f vol=%d art=%@ lyrics=%@ line=%d word=%d \"%@\"",
                             s?.player.rawValue ?? "-", s?.artist ?? "-", s?.title ?? "-", monitor.position(), s?.duration ?? 0,
                             s?.volume ?? -1, monitor.artwork == nil ? "no" : "yes", LyricEngine.shared.status.headline,
                             f.index ?? -1, f.wordIndex ?? -1, f.current?.text ?? ""))
        default: Log.write("debug: unknown command \(command)")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showGallery()
        return true
    }

    private func exitIfAlreadyRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0 != .current }
        guard let other = others.first else { return false }
        Log.write("another Lyrik instance is running (\(other.processIdentifier)), exiting this one")
        other.activate()
        NSApp.terminate(nil)
        return true
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusImage(playing: false)
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Lyrik"
        }
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.contentViewController = NSHostingController(rootView: MenuBarPopover(
            openWindow: { [weak self] in self?.popover.performClose(nil); self?.showGallery() },
            quit: { NSApp.terminate(nil) }))

        NowPlayingMonitor.shared.$sample
            .map { $0?.state == .playing }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in self?.statusItem.button?.image = self?.statusImage(playing: playing) }
            .store(in: &cancellables)
    }

    private func statusImage(playing: Bool) -> NSImage? {
        let image = NSImage(systemSymbolName: playing ? "text.bubble.fill" : "text.bubble",
                            accessibilityDescription: "Lyrik")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        image?.isTemplate = true
        return image
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NowPlayingMonitor.shared.poll()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let settings = AppSettings.shared
        let pinned = settings.pinned.isEmpty ? [settings.style] : settings.pinned
        for style in pinned {
            let item = NSMenuItem(title: style.name, action: #selector(pickStyle(_:)), keyEquivalent: "")
            item.representedObject = style.rawValue
            item.state = settings.style == style ? .on : .off
            item.image = NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Present Lyrics", action: #selector(presentLyrics), keyEquivalent: "p").target = self
        for (i, screen) in NSScreen.screens.enumerated() {
            let item = NSMenuItem(title: "Present Full Screen on \(screen.localizedName)", action: #selector(presentOnScreen(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            item.indentationLevel = 1
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Lyrik…", action: #selector(openGallery), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Show Log", action: #selector(showLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Lyrik", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func pickStyle(_ item: NSMenuItem) {
        if let raw = item.representedObject as? String, let s = LyricStyle(rawValue: raw) { AppSettings.shared.style = s }
    }

    @objc private func openGallery() { showGallery() }

    @objc private func presentLyrics() { PresentWindowController.shared.present() }

    @objc private func presentOnScreen(_ item: NSMenuItem) {
        guard NSScreen.screens.indices.contains(item.tag) else { return }
        PresentWindowController.shared.present(on: NSScreen.screens[item.tag], fullScreen: true)
    }

    @objc private func showLog() { NSWorkspace.shared.open(Log.fileURL) }

    func showGallery() {
        if gallery == nil { gallery = GalleryWindowController() }
        gallery?.present()
    }
}
