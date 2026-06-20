import AppKit
import CoreGraphics
import Foundation
import LifeReplayCore
import OSLog

@MainActor
final class MacActivityCollector {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "ActivityCollector")
    private let idleThreshold: TimeInterval
    private let onEvent: (ActivityEvent) -> Void
    private let browserDomainReader = BrowserDomainReader()
    private let windowTitleReader = WindowTitleReader()
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var isIdle = false
    private var lastBrowserDomain: String?
    private var lastBrowserDomainBundleID: String?

    private(set) var isRunning = false

    init(idleThreshold: TimeInterval = 90, onEvent: @escaping (ActivityEvent) -> Void) {
        self.idleThreshold = idleThreshold
        self.onEvent = onEvent
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let bundleIdentifier = app.bundleIdentifier
            let appName = app.localizedName
            let processIdentifier = app.processIdentifier
            let timestamp = Date()
            Task { @MainActor in
                self?.recordApplication(
                    bundleIdentifier: bundleIdentifier,
                    appName: appName,
                    processIdentifier: processIdentifier,
                    timestamp: timestamp
                )
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollIdleState()
            }
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            recordApplication(
                bundleIdentifier: app.bundleIdentifier,
                appName: app.localizedName,
                processIdentifier: app.processIdentifier,
                timestamp: Date()
            )
        }

        logger.info("Mac activity collector started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        timer?.invalidate()
        timer = nil
        isIdle = false
        lastBrowserDomain = nil
        lastBrowserDomainBundleID = nil

        logger.info("Mac activity collector stopped")
    }

    private func recordApplication(bundleIdentifier: String?, appName: String?, processIdentifier: pid_t?, timestamp: Date) {
        let windowTitle = windowTitleReader.frontWindowTitle(processIdentifier: processIdentifier)
        let event = ActivityEvent(
            timestamp: timestamp,
            kind: .appActivated,
            appBundleID: bundleIdentifier,
            appName: appName,
            windowTitle: windowTitle
        )
        logger.debug("Activated app: \(event.appName ?? "Unknown", privacy: .public)")
        onEvent(event)
        recordBrowserDomainIfAvailable(bundleIdentifier: bundleIdentifier, timestamp: timestamp)
    }

    private func pollIdleState() {
        let seconds = secondsSinceRecentInput()
        if seconds >= idleThreshold, !isIdle {
            isIdle = true
            onEvent(ActivityEvent(timestamp: Date(), kind: .idleStart))
            logger.info("Idle started after \(seconds, format: .fixed(precision: 1)) seconds")
        } else if seconds < idleThreshold, isIdle {
            isIdle = false
            onEvent(ActivityEvent(timestamp: Date(), kind: .idleEnd))
            logger.info("Idle ended")
        }
    }

    private func secondsSinceRecentInput() -> TimeInterval {
        let eventTypes: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    private func recordBrowserDomainIfAvailable(bundleIdentifier: String?, timestamp: Date) {
        guard let domain = browserDomainReader.domainForFrontmostBrowser(bundleIdentifier: bundleIdentifier) else {
            return
        }
        guard domain != lastBrowserDomain || bundleIdentifier != lastBrowserDomainBundleID else {
            return
        }

        lastBrowserDomain = domain
        lastBrowserDomainBundleID = bundleIdentifier

        let event = ActivityEvent(
            timestamp: timestamp,
            kind: .browserDomain,
            appBundleID: bundleIdentifier,
            browserDomain: domain
        )
        logger.debug("Browser domain: \(domain, privacy: .public)")
        onEvent(event)
    }
}
