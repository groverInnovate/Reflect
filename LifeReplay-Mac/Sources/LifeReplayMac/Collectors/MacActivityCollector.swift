import AppKit
import CoreGraphics
import Foundation
import LifeReplayCore
import OSLog

@MainActor
final class MacActivityCollector {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "ActivityCollector")
    private let idleThreshold: TimeInterval
    private let timerInterval: TimeInterval = 15
    private let suspensionGapThreshold: TimeInterval
    private let onEvent: (ActivityEvent) -> Void
    private let browserDomainReader = BrowserDomainReader()
    private let windowTitleReader = WindowTitleReader()
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var isIdle = false
    private var frontmostBundleIdentifier: String?
    private var lastBrowserDomain: String?
    private var lastBrowserDomainBundleID: String?
    private var lastIdlePollAt: Date?

    private(set) var isRunning = false

    init(idleThreshold: TimeInterval = 90, onEvent: @escaping (ActivityEvent) -> Void) {
        self.idleThreshold = idleThreshold
        self.suspensionGapThreshold = max(5 * 60, idleThreshold * 2)
        self.onEvent = onEvent
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
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
        observers.append(activationObserver)

        let sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordSystemSleep()
            }
        }
        observers.append(sleepObserver)

        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordSystemWake()
            }
        }
        observers.append(wakeObserver)

        lastIdlePollAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
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

        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
        isIdle = false
        frontmostBundleIdentifier = nil
        lastBrowserDomain = nil
        lastBrowserDomainBundleID = nil
        lastIdlePollAt = nil

        logger.info("Mac activity collector stopped")
    }

    func captureCurrentBrowserDomain() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        frontmostBundleIdentifier = app.bundleIdentifier
        return recordBrowserDomainIfAvailable(
            bundleIdentifier: app.bundleIdentifier,
            timestamp: Date(),
            allowDuplicate: true
        )
    }

    private func recordApplication(bundleIdentifier: String?, appName: String?, processIdentifier: pid_t?, timestamp: Date) {
        frontmostBundleIdentifier = bundleIdentifier
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
        _ = recordBrowserDomainIfAvailable(bundleIdentifier: bundleIdentifier, timestamp: timestamp)
    }

    private func pollIdleState() {
        let now = Date()
        recordSuspensionGapIfNeeded(now: now)
        lastIdlePollAt = now

        let seconds = secondsSinceRecentInput()
        if seconds >= idleThreshold, !isIdle {
            isIdle = true
            onEvent(ActivityEvent(timestamp: now, kind: .idleStart))
            logger.info("Idle started after \(seconds, format: .fixed(precision: 1)) seconds")
        } else if seconds < idleThreshold, isIdle {
            isIdle = false
            onEvent(ActivityEvent(timestamp: now, kind: .idleEnd))
            logger.info("Idle ended")
        }

        _ = recordBrowserDomainIfAvailable(bundleIdentifier: frontmostBundleIdentifier, timestamp: now)
    }

    private func recordSuspensionGapIfNeeded(now: Date) {
        guard let lastIdlePollAt else { return }
        let elapsed = now.timeIntervalSince(lastIdlePollAt)
        guard elapsed >= suspensionGapThreshold else { return }

        let inferredStart = lastIdlePollAt.addingTimeInterval(idleThreshold)
        guard inferredStart < now else { return }

        if !isIdle {
            onEvent(ActivityEvent(timestamp: inferredStart, kind: .idleStart, appName: "Mac sleep"))
            onEvent(ActivityEvent(timestamp: now, kind: .idleEnd, appName: "Mac wake"))
            logger.info("Recorded inferred sleep/away interval after timer gap of \(elapsed, format: .fixed(precision: 1)) seconds")
        }
    }

    private func recordSystemSleep() {
        guard !isIdle else { return }
        isIdle = true
        onEvent(ActivityEvent(timestamp: Date(), kind: .idleStart, appName: "Mac sleep"))
        logger.info("Idle started because macOS is going to sleep")
    }

    private func recordSystemWake() {
        guard isIdle else { return }
        isIdle = false
        let timestamp = Date()
        onEvent(ActivityEvent(timestamp: timestamp, kind: .idleEnd, appName: "Mac wake"))
        logger.info("Idle ended because macOS woke")

        if let app = NSWorkspace.shared.frontmostApplication {
            recordApplication(
                bundleIdentifier: app.bundleIdentifier,
                appName: app.localizedName,
                processIdentifier: app.processIdentifier,
                timestamp: timestamp
            )
        }
    }

    private func secondsSinceRecentInput() -> TimeInterval {
        let eventTypes: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    private func recordBrowserDomainIfAvailable(
        bundleIdentifier: String?,
        timestamp: Date,
        allowDuplicate: Bool = false
    ) -> String? {
        guard let domain = browserDomainReader.domainForFrontmostBrowser(bundleIdentifier: bundleIdentifier) else {
            return nil
        }
        guard allowDuplicate || domain != lastBrowserDomain || bundleIdentifier != lastBrowserDomainBundleID else {
            return domain
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
        return domain
    }
}
