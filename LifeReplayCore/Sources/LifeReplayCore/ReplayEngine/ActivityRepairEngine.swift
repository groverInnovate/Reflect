import Foundation

public struct ActivityRepairConfiguration: Sendable {
    public var minimumGapToRepair: TimeInterval
    public var idleStartOffset: TimeInterval

    public init(
        minimumGapToRepair: TimeInterval = 2 * 60 * 60,
        idleStartOffset: TimeInterval = 90
    ) {
        self.minimumGapToRepair = minimumGapToRepair
        self.idleStartOffset = idleStartOffset
    }
}

public struct ActivityRepairEngine: Sendable {
    private let configuration: ActivityRepairConfiguration

    public init(configuration: ActivityRepairConfiguration = .init()) {
        self.configuration = configuration
    }

    public func inferredIdleEvents(from events: [ActivityEvent]) -> [ActivityEvent] {
        let ordered = events.sorted { $0.timestamp < $1.timestamp }
        guard ordered.count >= 2 else { return [] }

        var repairs: [ActivityEvent] = []

        for pair in zip(ordered, ordered.dropFirst()) {
            let previous = pair.0
            let next = pair.1
            let gap = next.timestamp.timeIntervalSince(previous.timestamp)
            // A missing signal is not proof that the user slept. Only repair
            // genuinely long gaps, where treating the interval as away time is
            // safer than silently charging it to the last visible app.
            guard gap >= configuration.minimumGapToRepair else { continue }
            guard previous.kind != .idleStart, previous.kind != .idleEnd else { continue }
            guard next.kind != .idleStart, next.kind != .idleEnd else { continue }

            let idleStart = min(
                previous.timestamp.addingTimeInterval(configuration.idleStartOffset),
                next.timestamp
            )
            guard idleStart < next.timestamp else { continue }

            repairs.append(ActivityEvent(
                timestamp: idleStart,
                kind: .idleStart,
                appName: "Inferred away/sleep",
                source: "mac-repair"
            ))
            repairs.append(ActivityEvent(
                timestamp: next.timestamp,
                kind: .idleEnd,
                appName: "Inferred return",
                source: "mac-repair"
            ))
        }

        return repairs
    }
}
