import Foundation

/// The maximum time we are willing to attribute to a surface without a fresh
/// observation. A state-change event says where the user was; a heartbeat says
/// that the collector is still watching. Once both stop, assigning the gap to
/// the last app is a lie, so the gap becomes explicitly unobserved.
public struct ActivityTimelineConfiguration: Sendable {
    public var maximumObservedGap: TimeInterval

    public init(maximumObservedGap: TimeInterval = 120) {
        self.maximumObservedGap = max(30, maximumObservedGap)
    }
}

public struct ActivityTimelineEngine: Sendable {
    private let configuration: ActivityTimelineConfiguration

    public init(configuration: ActivityTimelineConfiguration = .init()) {
        self.configuration = configuration
    }

    public func blocks(
        from events: [ActivityEvent],
        resolver: CategoryResolver,
        now: Date
    ) -> [TimelineBlock] {
        let orderedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let idleIntervals = idleIntervals(from: orderedEvents, now: now)
        let meaningfulEvents = orderedEvents.filter(isMeaningful)
        var blocks: [TimelineBlock] = []

        for (index, event) in meaningfulEvents.enumerated() {
            guard event.timestamp < now else { continue }
            let nextTimestamp = meaningfulEvents.dropFirst(index + 1).first?.timestamp ?? now
            guard nextTimestamp > event.timestamp else { continue }

            let observedEnd = min(
                nextTimestamp,
                event.timestamp.addingTimeInterval(configuration.maximumObservedGap)
            )
            blocks += makeBlocks(
                from: event.timestamp,
                to: observedEnd,
                event: event,
                resolver: resolver,
                idleIntervals: idleIntervals,
                kind: .observed
            )

            if nextTimestamp > observedEnd {
                blocks += makeBlocks(
                    from: observedEnd,
                    to: nextTimestamp,
                    event: event,
                    resolver: resolver,
                    idleIntervals: idleIntervals,
                    kind: .unobserved
                )
            }
        }

        blocks += idleIntervals.map { interval in
            TimelineBlock(
                start: interval.start,
                end: interval.end,
                label: "Idle / away",
                category: .neutral,
                detail: "No keyboard or mouse input, or macOS sleep",
                kind: .idle
            )
        }

        return blocks
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }

    private func makeBlocks(
        from start: Date,
        to end: Date,
        event: ActivityEvent,
        resolver: CategoryResolver,
        idleIntervals: [(start: Date, end: Date)],
        kind: TimelineBlockKind
    ) -> [TimelineBlock] {
        activeIntervals(from: start, to: end, excluding: idleIntervals).map { interval in
            TimelineBlock(
                start: interval.start,
                end: interval.end,
                label: kind == .unobserved ? "Unobserved / away" : resolver.displayName(for: event),
                category: kind == .unobserved ? .neutral : resolver.category(for: event),
                detail: kind == .unobserved
                    ? "No fresh activity signal; time is not assigned to an app"
                    : event.windowTitle,
                kind: kind
            )
        }
    }

    private func isMeaningful(_ event: ActivityEvent) -> Bool {
        switch event.kind {
        case .appActivated, .browserDomain, .heartbeat:
            return true
        case .idleStart, .idleEnd:
            return false
        }
    }

    private func idleIntervals(
        from events: [ActivityEvent],
        now: Date
    ) -> [(start: Date, end: Date)] {
        var intervals: [(start: Date, end: Date)] = []
        var idleStart: Date?

        for event in events {
            switch event.kind {
            case .idleStart:
                if idleStart == nil {
                    idleStart = event.timestamp
                }
            case .idleEnd:
                if let start = idleStart, event.timestamp > start {
                    intervals.append((start, min(event.timestamp, now)))
                }
                idleStart = nil
            case .appActivated, .browserDomain, .heartbeat:
                continue
            }
        }

        if let start = idleStart, now > start {
            intervals.append((start, now))
        }

        return intervals.filter { $0.end > $0.start }
    }

    private func activeIntervals(
        from start: Date,
        to end: Date,
        excluding idleIntervals: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        guard end > start else { return [] }
        var intervals = [(start: start, end: end)]

        for idle in idleIntervals {
            intervals = intervals.flatMap { active in
                let overlapStart = max(active.start, idle.start)
                let overlapEnd = min(active.end, idle.end)
                guard overlapEnd > overlapStart else { return [active] }

                var remaining: [(start: Date, end: Date)] = []
                if active.start < overlapStart {
                    remaining.append((active.start, overlapStart))
                }
                if overlapEnd < active.end {
                    remaining.append((overlapEnd, active.end))
                }
                return remaining
            }
        }

        return intervals.filter { $0.end > $0.start }
    }
}
