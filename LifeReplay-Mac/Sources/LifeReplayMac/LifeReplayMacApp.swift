import AppKit
import LifeReplayCore
import OSLog

@MainActor
@main
final class LifeReplayMacApp: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "App")
    private let permissions = PermissionController()
    private let notifications = DriftNotificationController()
    private var statusItem: NSStatusItem?
    private var store: LifeReplayStore?
    private var dashboard: DashboardWindowController?
    private var categoryEditor: CategoryEditorWindowController?
    private var eventCount = 0
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
    }

    private func updateMenu() {
        statusItem?.button?.title = "Life Replay \(eventCount)"

        let menu = NSMenu()
        let toggleTitle = collector.isRunning ? "Pause Collection" : "Resume Collection"
        let accessibilityTitle = permissions.isAccessibilityTrusted ? "Accessibility: Allowed" : "Accessibility: Needs Approval"
        menu.addItem(NSMenuItem(title: toggleTitle, action: #selector(toggleCollection), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Raw events today: \(eventCount)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Generate Daily Replay", action: #selector(generateDailyReplay), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Edit Categories", action: #selector(openCategoryEditor), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: accessibilityTitle, action: #selector(requestAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Automation Settings", action: #selector(openAutomationSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
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
            dashboard = DashboardWindowController(store: store, permissions: permissions)
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

    @objc private func generateDailyReplay() {
        guard let store else { return }
        _ = store.generateDailyReplay()
        dashboard?.reload()
        updateMenu()
    }

    @objc private func requestAccessibility() {
        permissions.requestAccessibilityPermission()
        if !permissions.isAccessibilityTrusted {
            permissions.openAccessibilitySettings()
        }
        updateMenu()
    }

    @objc private func openAutomationSettings() {
        permissions.openAutomationSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
