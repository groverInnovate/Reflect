import Foundation

public struct FocusProtectionConfiguration: Sendable {
    public var minimumProtectedProductiveDuration: TimeInterval
    public var triggerEndTolerance: TimeInterval

    public init(
        minimumProtectedProductiveDuration: TimeInterval = 5 * 60,
        triggerEndTolerance: TimeInterval = 2
    ) {
        self.minimumProtectedProductiveDuration = minimumProtectedProductiveDuration
        self.triggerEndTolerance = triggerEndTolerance
    }
}

public struct FocusProtectionSignal: Equatable, Sendable {
    public var triggerName: String
    public var previousContext: String
    public var productiveMinutes: Int

    public init(triggerName: String, previousContext: String, productiveMinutes: Int) {
        self.triggerName = triggerName
        self.previousContext = previousContext
        self.productiveMinutes = productiveMinutes
    }
}

public struct FocusProtectionEngine: Sendable {
    private let configuration: FocusProtectionConfiguration
    private let focusEngine: FocusEngine
    private let resolver: CategoryResolver

    public init(
        configuration: FocusProtectionConfiguration = .init(),
        focusEngine: FocusEngine = .init(),
        resolver: CategoryResolver = .init()
    ) {
        self.configuration = configuration
        self.focusEngine = focusEngine
        self.resolver = resolver
    }

    public func signal(for event: ActivityEvent, events: [ActivityEvent]) -> FocusProtectionSignal? {
        guard event.kind == .appActivated || event.kind == .browserDomain else { return nil }
        guard resolver.category(for: event) == .distracting else { return nil }

        let eventsThroughTrigger = events
            .filter { $0.timestamp <= event.timestamp }
            .sorted { $0.timestamp < $1.timestamp }
        let analysis = focusEngine.analyze(events: eventsThroughTrigger, now: event.timestamp)

        guard let previousSession = analysis.sessions
            .filter({ session in
                guard session.category == .productive, let end = session.end else { return false }
                let endedAtTrigger = abs(end.timeIntervalSince(event.timestamp)) <= configuration.triggerEndTolerance
                let activeSeconds = max(0, end.timeIntervalSince(session.start) - Double(session.idleSeconds))
                return endedAtTrigger && activeSeconds >= configuration.minimumProtectedProductiveDuration
            })
            .max(by: { lhs, rhs in
                (lhs.end ?? lhs.start) < (rhs.end ?? rhs.start)
            })
        else {
            return nil
        }

        let end = previousSession.end ?? event.timestamp
        let productiveMinutes = max(1, Int((end.timeIntervalSince(previousSession.start) - Double(previousSession.idleSeconds)) / 60))
        return FocusProtectionSignal(
            triggerName: resolver.displayName(for: event),
            previousContext: previousSession.primaryAppName ?? "productive work",
            productiveMinutes: productiveMinutes
        )
    }
}
