import AppKit
import LifeReplayCore
import OSLog

@MainActor
@main
final class LifeReplayMacApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "App")
    private let permissions = PermissionController()
    private let notifications = DriftNotificationController()
    private var statusItem: NSStatusItem?
    private var store: LifeReplayStore?
    private var dashboard: DashboardWindowController?
    private var categoryEditor: CategoryEditorWindowController?
    private var focusSettingsWindow: FocusSettingsWindowController?
    private var dataStatusWindow: DataStatusWindowController?
    private var replayHistoryWindow: ReplayHistoryWindowController?
    private var eventCount = 0
    private var notificationSummary: DriftNotificationController.AuthorizationSummary = .unknown
    private lazy var collector = MacActivityCollector { [weak self] event in
        guard let self else { return }
        self.store?.record(event)
        self.eventCount = self.store?.eventsForToday().count ?? self.eventCount + 1
        let newDrifts = self.store?.refreshTodayAnalysis().newDrifts ?? []
        for drift in newDrifts {
            self.notifications.notify(driftEvent: drift)
        }
        self.dashboard?.reload()
        self.updateMenu()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = LifeReplayMacApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("LifeReplayMac launched")
        do {
            store = try LifeReplayStore()
            eventCount = store?.eventsForToday().count ?? 0
        } catch {
            logger.error("Failed to initialize local store: \(error.localizedDescription, privacy: .public)")
        }
        configureStatusItem()
        notifications.requestAuthorizationIfNeeded()
        collector.start()
        updateMenu()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Life Replay"
        statusItem = item
        updateNotificationSummary()
    }

    private func updateMenu() {
        statusItem?.button?.title = "Life Replay \(eventCount)"

        let menu = NSMenu()
        menu.delegate = self
        let toggleTitle = collector.isRunning ? "Pause Collection" : "Resume Collection"
        let accessibilityTitle = permissions.isAccessibilityTrusted ? "Accessibility: Allowed" : "Accessibility: Needs Approval"
        menu.addItem(NSMenuItem(title: toggleTitle, action: #selector(toggleCollection), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Raw events today: \(eventCount)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Replay History", action: #selector(openReplayHistory), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Generate Daily Replay", action: #selector(generateDailyReplay), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Export Daily Replay...", action: #selector(exportDailyReplay), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "Export Debug CSVs...", action: #selector(exportDebugCSVs), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Edit Categories", action: #selector(openCategoryEditor), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Focus Drift Settings", action: #selector(openFocusSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Data Status", action: #selector(openDataStatus), keyEquivalent: "i"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: accessibilityTitle, action: #selector(requestAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Notifications: \(notificationSummary.rawValue)", action: #selector(requestNotifications), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Send Test Notification", action: #selector(sendTestNotification), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Current Browser Tab", action: #selector(captureCurrentBrowserTab), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Permission Diagnostics", action: #selector(showPermissionDiagnostics), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Automation Settings", action: #selector(openAutomationSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            updateNotificationSummary()
            updateMenu()
        }
    }

    private func updateNotificationSummary() {
        notifications.authorizationSummary { [weak self] summary in
            self?.notificationSummary = summary
            self?.updateMenu()
        }
    }

    @objc private func toggleCollection() {
        if collector.isRunning {
            collector.stop()
        } else {
            collector.start()
        }
        updateMenu()
    }

    @objc private func openDashboard() {
        logger.info("Dashboard requested")
        guard let store else {
            let alert = NSAlert()
            alert.messageText = "Local store unavailable"
            alert.informativeText = "Life Replay could not open its SwiftData store. Check Console logs for the underlying error."
            alert.runModal()
            return
        }

        if dashboard == nil {
            dashboard = DashboardWindowController(store: store, permissions: permissions, notifications: notifications)
        }
        dashboard?.reload()
        dashboard?.showWindow(nil)
        NSApp.activate()
    }

    @objc private func openCategoryEditor() {
        guard let store else { return }
        if categoryEditor == nil {
            categoryEditor = CategoryEditorWindowController(store: store)
        }
        categoryEditor?.reload()
        categoryEditor?.showWindow(nil)
        NSApp.activate()
    }

    @objc private func openFocusSettings() {
        guard let store else { return }
        if focusSettingsWindow == nil {
            focusSettingsWindow = FocusSettingsWindowController(store: store)
        }
        focusSettingsWindow?.reload()
        focusSettingsWindow?.showWindow(nil)
        NSApp.activate()
    }

    @objc private func openDataStatus() {
        guard let store else { return }
        if dataStatusWindow == nil {
            dataStatusWindow = DataStatusWindowController(store: store)
        }
        dataStatusWindow?.reload()
        dataStatusWindow?.showWindow(nil)
        NSApp.activate()
    }

    @objc private func openReplayHistory() {
        guard let store else { return }
        if replayHistoryWindow == nil {
            replayHistoryWindow = ReplayHistoryWindowController(store: store)
        }
        replayHistoryWindow?.reload()
        replayHistoryWindow?.showWindow(nil)
        NSApp.activate()
    }

    @objc private func generateDailyReplay() {
        guard let store else { return }
        Task { @MainActor in
            _ = await store.generateDailyReplayWithNarrative()
            dashboard?.reload()
            updateMenu()
        }
    }

    @objc private func exportDailyReplay() {
        guard let store else { return }
        let replay = store.existingDailyReplay() ?? store.generateDailyReplay()
        guard let replay else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Life Replay \(Date.now.formatted(.iso8601.year().month().day())).md"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try store.markdownForDailyReplay(replay).write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    self?.logger.error("Failed to export daily replay: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @objc private func exportDebugCSVs() {
        guard let store else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try store.exportTodayDebugData(to: url)
                } catch {
                    self?.logger.error("Failed to export debug CSVs: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @objc private func requestAccessibility() {
        permissions.requestAccessibilityPermission()
        if !permissions.isAccessibilityTrusted {
            permissions.openAccessibilitySettings()
        }
        updateMenu()
    }

    @objc private func requestNotifications() {
        if notificationSummary == .denied {
            permissions.openNotificationSettings()
            return
        }
        notifications.requestAuthorizationIfNeeded(force: true)
        updateNotificationSummary()
    }

    @objc private func sendTestNotification() {
        notifications.sendTestNotification()
        updateNotificationSummary()
    }

    @objc private func captureCurrentBrowserTab() {
        let domain = collector.captureCurrentBrowserDomain()
        let alert = NSAlert()
        alert.messageText = "Browser Capture"
        if let domain {
            alert.informativeText = "Captured domain: \(domain)"
        } else {
            alert.informativeText = "No browser domain captured. Bring Safari, Chrome, Brave, Edge, or Vivaldi to the front and approve Automation if macOS asks."
        }
        alert.runModal()
    }

    @objc private func openAutomationSettings() {
        permissions.openAutomationSettings()
    }

    @objc private func showPermissionDiagnostics() {
        let alert = NSAlert()
        alert.messageText = "Life Replay Permission Diagnostics"
        alert.informativeText = """
        \(permissions.diagnosticSummary)
        Notifications: \(notificationSummary.rawValue)
        """
        alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
