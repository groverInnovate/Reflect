import AppKit
import LifeReplayCore
import OSLog

@MainActor
@main
final class LifeReplayMacApp: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "App")
    private var statusItem: NSStatusItem?
    private var eventCount = 0
    private lazy var collector = MacActivityCollector { [weak self] _ in
        self?.eventCount += 1
        self?.updateMenu()
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
        configureStatusItem()
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
        menu.addItem(NSMenuItem(title: toggleTitle, action: #selector(toggleCollection), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Raw events today: \(eventCount)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d"))
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
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
