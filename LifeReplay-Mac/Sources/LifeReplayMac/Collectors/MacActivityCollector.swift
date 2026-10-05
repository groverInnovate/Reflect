import AppKit
import CoreGraphics
import Foundation
import LifeReplayCore
import OSLog

@MainActor
final class MacActivityCollector {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "ActivityCollector")
    private var idleThreshold: TimeInterval
    private let timerInterval: TimeInterval = 5
    private let heartbeatInterval: TimeInterval = 15
    private let suspensionGapThreshold: TimeInterval
    private let onEvent: (CoreActivityEvent) -> Void
    private let browserDomainReader = BrowserDomainReader()
    private let windowTitleReader = WindowTitleReader()
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var isIdle = false
    private var sessionInactive = false
    private var needsInputAfter: Date?
    private var frontmostBundleIdentifier: String?
    private var lastBrowserDomain: String?
    private var lastBrowserDomainBundleID: String?
    private var lastIdlePollAt: Date?
    private var lastActiveEvidenceAt: Date?

    private(set) var isRunning = false
    var browserCaptureIssue: String? { browserDomainReader.lastFailure }

    init(idleThreshold: TimeInterval = 90, onEvent: @escaping (CoreActivityEvent) -> Void) {
        self.idleThreshold = idleThreshold
        self.suspensionGapThreshold = max(5 * 60, idleThreshold * 2)
        self.onEvent = onEvent
    }

    func updateIdleThreshold(_ seconds: TimeInterval) {
        let updated = max(30, seconds)
        guard updated != idleThreshold else { return }
        let restart = isRunning
        if restart { stop() }
        idleThreshold = updated
        if restart { start() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        sessionInactive = false
        needsInputAfter = nil

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

        let sessionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sessionInactive = true; self?.recordSystemSleep() }
        }
        observers.append(sessionObserver)
        let activeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sessionInactive = false; self?.recordSystemWake() }
        }
        observers.append(activeObserver)
        let displaySleep = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recordSystemSleep() }
        }
        observers.append(displaySleep)
        let displayWake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recordSystemWake() }
        }
        observers.append(displayWake)

        lastIdlePollAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollIdleState()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }

        // Clear a persisted idle interval after an interrupted process, then
        // inspect current input before assigning any fresh time.
        let startedAt = Date()
        onEvent(CoreActivityEvent(timestamp: startedAt, kind: .idleEnd))
        if secondsSinceRecentInput() >= idleThreshold {
            isIdle = true
            onEvent(CoreActivityEvent(timestamp: startedAt, kind: .idleStart))
        } else if let app = NSWorkspace.shared.frontmostApplication {
            recordApplication(
                bundleIdentifier: app.bundleIdentifier,
                appName: app.localizedName,
                processIdentifier: app.processIdentifier,
                timestamp: startedAt
            )
        }

        logger.info("Mac activity collector started")
    }

    func stop() {
        guard isRunning else { return }
        onEvent(CoreActivityEvent(timestamp: Date(), kind: .trackingStopped))
        isRunning = false

        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
        isIdle = false
        sessionInactive = false
        needsInputAfter = nil
        frontmostBundleIdentifier = nil
        lastBrowserDomain = nil
        lastBrowserDomainBundleID = nil
        lastIdlePollAt = nil
        lastActiveEvidenceAt = nil

        logger.info("Mac activity collector stopped")
    }

    private func recordApplication(bundleIdentifier: String?, appName: String?, processIdentifier: pid_t?, timestamp: Date) {
        guard isRunning, !sessionInactive else { return }
        let seconds = secondsSinceRecentInput()
        if let needsInputAfter, Date().addingTimeInterval(-seconds) <= needsInputAfter { return }
        if seconds >= idleThreshold { return }
        needsInputAfter = nil
        if isIdle {
            isIdle = false
            onEvent(CoreActivityEvent(timestamp: timestamp, kind: .idleEnd))
        }
        // Returning to a browser must capture its domain even if its tab did not
        // change while another app was frontmost.
        if frontmostBundleIdentifier != bundleIdentifier {
            lastBrowserDomain = nil
            lastBrowserDomainBundleID = nil
        }
        frontmostBundleIdentifier = bundleIdentifier
        let windowTitle = windowTitleReader.frontWindowTitle(processIdentifier: processIdentifier)
        let event = CoreActivityEvent(
            timestamp: timestamp,
            kind: .appActivated,
            appBundleID: bundleIdentifier,
            appName: appName,
            windowTitle: windowTitle
        )
        logger.debug("Activated app: \(event.appName ?? "Unknown", privacy: .public)")
        onEvent(event)
        lastActiveEvidenceAt = timestamp
        _ = recordBrowserDomainIfAvailable(bundleIdentifier: bundleIdentifier, timestamp: timestamp)
    }

    private func pollIdleState() {
        guard isRunning else { return }
        let now = Date()
        recordSuspensionGapIfNeeded(now: now)
        lastIdlePollAt = now

        guard !sessionInactive else { return }
        let seconds = secondsSinceRecentInput()
        if let needsInputAfter, now.addingTimeInterval(-seconds) <= needsInputAfter { return }
        needsInputAfter = nil
        if seconds >= idleThreshold, !isIdle {
            isIdle = true
            let onset = now.addingTimeInterval(-(seconds - idleThreshold))
            onEvent(CoreActivityEvent(timestamp: max(onset, lastActiveEvidenceAt ?? onset), kind: .idleStart))
            logger.info("Idle started after \(seconds, format: .fixed(precision: 1)) seconds")
        } else if seconds < idleThreshold, isIdle {
            isIdle = false
            let resumedAt = now.addingTimeInterval(-seconds)
            onEvent(CoreActivityEvent(timestamp: resumedAt, kind: .idleEnd))
            if let app = NSWorkspace.shared.frontmostApplication {
                recordApplication(bundleIdentifier: app.bundleIdentifier, appName: app.localizedName,
                                  processIdentifier: app.processIdentifier, timestamp: resumedAt)
            }
            logger.info("Idle ended")
        }

        guard !isIdle else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if app.bundleIdentifier != frontmostBundleIdentifier {
            recordApplication(bundleIdentifier: app.bundleIdentifier, appName: app.localizedName,
                              processIdentifier: app.processIdentifier, timestamp: now)
        } else {
            let domain = recordBrowserDomainIfAvailable(bundleIdentifier: app.bundleIdentifier, timestamp: now)
            recordHeartbeatIfNeeded(at: now, domain: domain)
        }
    }

    private func recordSuspensionGapIfNeeded(now: Date) {
        guard let lastIdlePollAt, now.timeIntervalSince(lastIdlePollAt) >= suspensionGapThreshold else { return }
        // A delayed timer proves missing observations, not sleep. End attribution
        // at the last poll and let actual sleep notifications describe away time.
        if !isIdle {
            onEvent(CoreActivityEvent(timestamp: lastIdlePollAt, kind: .trackingStopped))
            lastActiveEvidenceAt = nil
            frontmostBundleIdentifier = nil
        }
    }

    private func recordSystemSleep() {
        guard isRunning else { return }
        needsInputAfter = Date()
        guard !isIdle else { return }
        isIdle = true
        lastActiveEvidenceAt = nil
        onEvent(CoreActivityEvent(timestamp: Date(), kind: .idleStart, appName: "Mac sleep"))
        logger.info("Idle started because macOS is going to sleep")
    }

    private func recordSystemWake() {
        guard isRunning else { return }
        // Waking for background maintenance is not user activity. The next input
        // poll ends idle and captures the current surface.
        lastIdlePollAt = Date()
        pollIdleState()
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
            lastBrowserDomain = nil
            lastBrowserDomainBundleID = nil
            return nil
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier else { return nil }
        guard allowDuplicate || domain != lastBrowserDomain || bundleIdentifier != lastBrowserDomainBundleID else {
            return domain
        }

        lastBrowserDomain = domain
        lastBrowserDomainBundleID = bundleIdentifier

        let event = CoreActivityEvent(
            timestamp: timestamp,
            kind: .browserDomain,
            appBundleID: bundleIdentifier,
            appName: NSWorkspace.shared.frontmostApplication?.localizedName,
            windowTitle: windowTitleReader.frontWindowTitle(processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier),
            browserDomain: domain
        )
        logger.debug("Browser domain: \(domain, privacy: .public)")
        onEvent(event)
        lastActiveEvidenceAt = timestamp
        return domain
    }

    private func recordHeartbeatIfNeeded(at timestamp: Date, domain: String?) {
        guard let lastActiveEvidenceAt,
              timestamp.timeIntervalSince(lastActiveEvidenceAt) >= heartbeatInterval,
              let app = NSWorkspace.shared.frontmostApplication
        else { return }

        if app.bundleIdentifier != frontmostBundleIdentifier {
            recordApplication(
                bundleIdentifier: app.bundleIdentifier,
                appName: app.localizedName,
                processIdentifier: app.processIdentifier,
                timestamp: timestamp
            )
            return
        }

        let event = CoreActivityEvent(
            timestamp: timestamp,
            kind: .heartbeat,
            appBundleID: app.bundleIdentifier,
            appName: app.localizedName,
            windowTitle: windowTitleReader.frontWindowTitle(processIdentifier: app.processIdentifier),
            browserDomain: domain
        )
        onEvent(event)
        self.lastActiveEvidenceAt = timestamp
    }
}
