import AppKit
import OSLog
import UserNotifications

@MainActor
@main
final class LifeReplayMacApp: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "App")
    private let permissions = PermissionController()
    private let launchAtLogin = LaunchAtLoginController()
    private var statusItem: NSStatusItem?
    private var store: LifeReplayStore?
    private var dashboard: DashboardWindowController?
    private var refreshTimer: Timer?
    private var collectionEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "collectionEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "collectionEnabled") }
    }
    private lazy var collector = MacActivityCollector { [weak self] event in
        guard let self else { return }
        if self.store?.record(event) == false { self.updateMenu() }
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = LifeReplayMacApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cancel reminders from earlier builds without requesting notification permission.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        do { store = try LifeReplayStore() }
        catch {
            logger.error("Store initialization failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Life Replay could not open your data"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let store {
            collector.updateIdleThreshold(store.focusSettings().idleThresholdSeconds)
            if collectionEnabled { collector.start() }
        }
        updateMenu()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.dashboard?.window?.isVisible == true { self.dashboard?.reload() }
                self.updateMenu()
            }
        }
        if let refreshTimer { RunLoop.main.add(refreshTimer, forMode: .common) }
        openDashboard()
    }

    func applicationWillTerminate(_ notification: Notification) { collector.stop() }

    private func updateMenu() {
        statusItem?.button?.image = NSImage(systemSymbolName: collector.isRunning ? "chart.bar.xaxis" : "pause.circle",
                                          accessibilityDescription: collector.isRunning ? "Life Replay — tracking" : "Life Replay — paused")
        statusItem?.button?.title = ""
        statusItem?.button?.toolTip = "Life Replay • \(collector.isRunning ? "Tracking" : "Paused")"
        let menu = NSMenu()
        let state = store?.lastError == nil ? (collector.isRunning ? "Tracking your Mac" : "Tracking paused") : "Activity could not be saved"
        menu.addItem(withTitle: state, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Life Replay", action: #selector(openDashboard), keyEquivalent: "d")
        menu.addItem(withTitle: collector.isRunning ? "Pause Tracking" : "Resume Tracking", action: #selector(toggleCollection), keyEquivalent: "p")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Life Replay", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem?.menu = menu
    }

    @objc private func toggleCollection() {
        if collector.isRunning { collector.stop(); collectionEnabled = false }
        else if store != nil { collector.start(); collectionEnabled = true }
        updateMenu()
        dashboard?.reload()
    }

    @objc private func openDashboard() {
        guard let store else { return }
        if dashboard == nil {
            dashboard = DashboardWindowController(store: store, permissions: permissions,
                trackingState: { [weak self] in self?.collector.isRunning ?? false },
                browserIssue: { [weak self] in self?.collector.browserCaptureIssue },
                toggleTracking: { [weak self] in self?.toggleCollection() },
                loginStatus: { [weak self] in self?.launchAtLogin.statusDescription ?? "Unavailable" },
                toggleLogin: { [weak self] in self?.launchAtLogin.toggle() },
                settingsChanged: { [weak self] in
                    self?.collector.updateIdleThreshold(store.focusSettings().idleThresholdSeconds)
                })
        }
        dashboard?.reload()
        dashboard?.showWindow(nil)
        NSApp.activate()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
