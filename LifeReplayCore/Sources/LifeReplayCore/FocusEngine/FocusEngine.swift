import Foundation

public struct FocusEngineConfiguration: Sendable {
    public var idleThresholdSeconds: TimeInterval
    public var sessionMinimumDuration: TimeInterval
    public var driftWindow: TimeInterval
    public var defaultBaselineSwitchesPerHour: Double
    public var productiveSessionMinimumDuration: TimeInterval

    public init(
        idleThresholdSeconds: TimeInterval = 90,
        sessionMinimumDuration: TimeInterval = 90,
        driftWindow: TimeInterval = 10 * 60,
        defaultBaselineSwitchesPerHour: Double = 12,
        productiveSessionMinimumDuration: TimeInterval = 5 * 60
    ) {
        self.idleThresholdSeconds = idleThresholdSeconds
        self.sessionMinimumDuration = sessionMinimumDuration
        self.driftWindow = driftWindow
        self.defaultBaselineSwitchesPerHour = defaultBaselineSwitchesPerHour
        self.productiveSessionMinimumDuration = productiveSessionMinimumDuration
    }
}

public struct FocusAnalysis {
    public var sessions: [FocusSession]
    public var driftEvents: [DriftEvent]
    public var focusScore: Int
}

public struct FocusEngine: Sendable {
    private let configuration: FocusEngineConfiguration
    private let resolver: CategoryResolver

    public init(
        configuration: FocusEngineConfiguration = .init(),
        resolver: CategoryResolver = .init()
    ) {
        self.configuration = configuration
        self.resolver = resolver
    }

    public func analyze(events: [ActivityEvent], now: Date? = nil) -> FocusAnalysis {
        let orderedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let sessions = buildSessions(from: orderedEvents, now: now)
        let drifts = detectDrift(in: orderedEvents, sessions: sessions)
        let score = score(sessions: sessions, driftEvents: drifts)
        return FocusAnalysis(sessions: sessions, driftEvents: drifts, focusScore: score)
    }

    public func score(sessions: [FocusSession], driftEvents: [DriftEvent]) -> Int {
        let trackedSeconds = sessions.reduce(0) { total, session in
            total + max(0, (session.end ?? session.start).timeIntervalSince(session.start) - Double(session.idleSeconds))
        }

        guard trackedSeconds > 0 else { return 0 }

        let productiveSeconds = sessions
            .filter { $0.category == .productive }
            .reduce(0) { total, session in
                total + max(0, (session.end ?? session.start).timeIntervalSince(session.start) - Double(session.idleSeconds))
            }

        let productiveContribution = min(90, Int((productiveSeconds / trackedSeconds) * 90))
        let expectedDriftToday = max(1.0, trackedSeconds / 3600)
        let driftRatio = min(1, Double(driftEvents.count) / expectedDriftToday)
        let driftContribution = Int((1 - driftRatio) * 10)
        return max(0, min(100, productiveContribution + driftContribution))
    }

    private func buildSessions(from events: [ActivityEvent], now: Date?) -> [FocusSession] {
        let meaningfulEvents = events.filter { $0.kind == .appActivated || $0.kind == .browserDomain }
        guard let first = meaningfulEvents.first else { return [] }

        var sessions: [FocusSession] = []
        var current = FocusSession(
            start: first.timestamp,
            category: resolver.category(for: first),
            primaryAppName: resolver.displayName(for: first),
            switchCount: 0
        )

        for event in meaningfulEvents.dropFirst() {
            let category = resolver.category(for: event)
            let gap = event.timestamp.timeIntervalSince(current.start)

            if category == current.category || gap < configuration.sessionMinimumDuration {
                current.end = event.timestamp
                current.switchCount += 1
                if current.primaryAppName == nil {
                    current.primaryAppName = resolver.displayName(for: event)
                }
                continue
            }

            current.end = event.timestamp
            sessions.append(current)
            current = FocusSession(
                start: event.timestamp,
                category: category,
                primaryAppName: resolver.displayName(for: event)
            )
        }

        current.end = now ?? meaningfulEvents.last?.timestamp ?? current.start
        sessions.append(current)
        return sessions
    }

    private func detectDrift(in events: [ActivityEvent], sessions: [FocusSession]) -> [DriftEvent] {
        sessions.compactMap { session in
            guard
                session.category == .productive,
                let end = session.end,
                end.timeIntervalSince(session.start) >= configuration.productiveSessionMinimumDuration
            else {
                return nil
            }

            let windowEnd = end.addingTimeInterval(configuration.driftWindow)
            let windowEvents = events.filter {
                ($0.kind == .appActivated || $0.kind == .browserDomain)
                    && $0.timestamp >= end
                    && $0.timestamp <= windowEnd
            }

            let distractingNames = windowEvents
                .filter { resolver.category(for: $0) == .distracting }
                .map { resolver.displayName(for: $0) }

            let baselineForWindow = configuration.defaultBaselineSwitchesPerHour * (configuration.driftWindow / 3600)
            let threshold = max(1, Int(ceil(2 * baselineForWindow)))

            guard windowEvents.count >= threshold, !distractingNames.isEmpty else {
                return nil
            }

            let severity = min(1, Double(windowEvents.count) / max(1, Double(threshold)))
            return DriftEvent(
                timestamp: windowEvents.first?.timestamp ?? end,
                precedingSessionID: session.id,
                triggerAppNames: Array(Set(distractingNames)).sorted(),
                switchCountInWindow: windowEvents.count,
                baselineSwitchRate: configuration.defaultBaselineSwitchesPerHour,
                severity: severity
            )
        }
    }
}
