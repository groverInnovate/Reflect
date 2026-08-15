import Foundation

public struct FocusEngineConfiguration: Sendable {
    public var idleThresholdSeconds: TimeInterval
    public var sessionMinimumDuration: TimeInterval
    public var driftWindow: TimeInterval
    public var defaultBaselineSwitchesPerHour: Double
    public var productiveSessionMinimumDuration: TimeInterval
    public var maximumObservedGap: TimeInterval

    public init(
        idleThresholdSeconds: TimeInterval = 90,
        sessionMinimumDuration: TimeInterval = 90,
        driftWindow: TimeInterval = 10 * 60,
        defaultBaselineSwitchesPerHour: Double = 12,
        productiveSessionMinimumDuration: TimeInterval = 5 * 60,
        maximumObservedGap: TimeInterval = 120
    ) {
        self.idleThresholdSeconds = idleThresholdSeconds
        self.sessionMinimumDuration = sessionMinimumDuration
        self.driftWindow = driftWindow
        self.defaultBaselineSwitchesPerHour = defaultBaselineSwitchesPerHour
        self.productiveSessionMinimumDuration = productiveSessionMinimumDuration
        self.maximumObservedGap = max(30, maximumObservedGap)
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

    /// Analyze observed time, optionally using prior days to calibrate the
    /// user's normal switching rate for this hour of day.
    public func analyze(
        events: [ActivityEvent],
        now: Date? = nil,
        historicalEvents: [ActivityEvent] = []
    ) -> FocusAnalysis {
        let orderedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let resolvedNow = now ?? orderedEvents.last?.timestamp ?? Date()
        let timeline = ActivityTimelineEngine(
            configuration: ActivityTimelineConfiguration(
                maximumObservedGap: configuration.maximumObservedGap
            )
        ).blocks(from: orderedEvents, resolver: resolver, now: resolvedNow)
        let sessions = buildSessions(from: timeline)
        let drifts = detectDrift(
            in: orderedEvents,
            sessions: sessions,
            historicalEvents: historicalEvents
        )
        let score = score(sessions: sessions, driftEvents: drifts)
        return FocusAnalysis(sessions: sessions, driftEvents: drifts, focusScore: score)
    }

    public func score(sessions: [FocusSession], driftEvents: [DriftEvent]) -> Int {
        let trackedSeconds = sessions.reduce(0.0) { total, session in
            total + activeDuration(of: session)
        }

        guard trackedSeconds > 0 else { return 0 }

        let productiveSeconds = sessions
            .filter { $0.category == .productive }
            .reduce(0.0) { total, session in
                total + activeDuration(of: session)
            }

        let productiveContribution = min(90, Int((productiveSeconds / trackedSeconds) * 90))
        let expectedDriftToday = max(1.0, trackedSeconds / 3600)
        let driftRatio = min(1, Double(driftEvents.count) / expectedDriftToday)
        let driftContribution = Int((1 - driftRatio) * 10)
        return max(0, min(100, productiveContribution + driftContribution))
    }

    private func activeDuration(of session: FocusSession) -> TimeInterval {
        guard let end = session.end else { return 0 }
        return max(0, end.timeIntervalSince(session.start) - Double(session.idleSeconds))
    }

    private func buildSessions(from blocks: [TimelineBlock]) -> [FocusSession] {
        var sessions: [FocusSession] = []
        var current: FocusSession?
        var primaryLabelDuration: TimeInterval = 0

        for block in blocks where block.kind == .observed && block.end > block.start {
            let duration = block.end.timeIntervalSince(block.start)

            if let current,
               current.category == block.category,
               abs(block.start.timeIntervalSince(current.end ?? current.start)) < 0.5 {
                let changedSurface = current.primaryAppName != block.label
                current.end = block.end
                if changedSurface {
                    current.switchCount += 1
                }
                if duration > primaryLabelDuration {
                    current.primaryAppName = block.label
                    primaryLabelDuration = duration
                }
                continue
            }

            if let current {
                sessions.append(current)
            }
            current = FocusSession(
                start: block.start,
                end: block.end,
                category: block.category,
                primaryAppName: block.label,
                switchCount: 0,
                idleSeconds: 0
            )
            primaryLabelDuration = duration
        }

        if let current {
            sessions.append(current)
        }
        return sessions
    }

    private func detectDrift(
        in events: [ActivityEvent],
        sessions: [FocusSession],
        historicalEvents: [ActivityEvent]
    ) -> [DriftEvent] {
        sessions.compactMap { session in
            guard
                session.category == .productive,
                let end = session.end,
                activeDuration(of: session) >= configuration.productiveSessionMinimumDuration
            else {
                return nil
            }

            let windowEnd = end.addingTimeInterval(configuration.driftWindow)
            let switchEvents = normalizedSwitchEvents(from: events).filter {
                $0.timestamp >= end && $0.timestamp <= windowEnd
            }
            let distractingNames = switchEvents
                .filter { resolver.category(for: $0) == .distracting }
                .map { resolver.displayName(for: $0) }

            let baseline = baselineSwitchRate(
                around: session.start,
                historicalEvents: historicalEvents
            )
            let baselineForWindow = baseline * (configuration.driftWindow / 3600)
            let threshold = max(2, Int(ceil(2 * baselineForWindow)))

            guard switchEvents.count >= threshold, !distractingNames.isEmpty else {
                return nil
            }

            let severity = min(1, Double(switchEvents.count) / Double(threshold))
            return DriftEvent(
                timestamp: switchEvents.first?.timestamp ?? end,
                precedingSessionID: session.id,
                triggerAppNames: Array(Set(distractingNames)).sorted(),
                switchCountInWindow: switchEvents.count,
                baselineSwitchRate: baseline,
                severity: severity
            )
        }
    }

    private func baselineSwitchRate(
        around date: Date,
        historicalEvents: [ActivityEvent]
    ) -> Double {
        let switchEvents = normalizedSwitchEvents(from: historicalEvents)
        let calendar = Calendar.autoupdatingCurrent
        let hour = calendar.component(.hour, from: date)
        let dayKeys = Set(switchEvents.map { calendar.startOfDay(for: $0.timestamp) })

        // The default is intentionally used until there are seven distinct
        // days. A handful of anomalous days should not redefine "normal".
        guard dayKeys.count >= 7 else {
            return configuration.defaultBaselineSwitchesPerHour
        }

        let rates = dayKeys.compactMap { day -> Double? in
            let count = switchEvents.filter {
                calendar.startOfDay(for: $0.timestamp) == day
                    && calendar.component(.hour, from: $0.timestamp) == hour
            }.count
            return Double(count)
        }.sorted()

        guard !rates.isEmpty else {
            return configuration.defaultBaselineSwitchesPerHour
        }
        let middle = rates.count / 2
        if rates.count.isMultiple(of: 2) {
            return (rates[middle - 1] + rates[middle]) / 2
        }
        return rates[middle]
    }

    /// App activation and browser-domain capture can describe the same user
    /// action at the same timestamp. Count that as one transition; otherwise a
    /// browser switch would inflate both drift severity and the user's baseline.
    private func normalizedSwitchEvents(from events: [ActivityEvent]) -> [ActivityEvent] {
        var normalized: [ActivityEvent] = []

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard event.kind == .appActivated || event.kind == .browserDomain else { continue }

            if let lastIndex = normalized.indices.last,
               normalized[lastIndex].timestamp == event.timestamp {
                if event.kind == .browserDomain {
                    normalized[lastIndex] = event
                }
            } else {
                normalized.append(event)
            }
        }
        return normalized
    }
}
