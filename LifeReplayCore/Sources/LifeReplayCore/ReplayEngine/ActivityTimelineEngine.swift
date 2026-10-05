import Foundation

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

    public func blocks(from events: [ActivityEvent], resolver: CategoryResolver, now: Date) -> [TimelineBlock] {
        // Stable ordering lets a domain refine a same-instant app activation.
        let ordered = events.enumerated().filter { $0.element.timestamp <= now }.sorted {
            if $0.element.timestamp != $1.element.timestamp { return $0.element.timestamp < $1.element.timestamp }
            let left = priority($0.element.kind), right = priority($1.element.kind)
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        var surface: ActivityEvent?
        var idle = false
        var paused = false
        var result: [TimelineBlock] = []

        for (index, event) in ordered.enumerated() {
            switch event.kind {
            case .idleStart:
                idle = true
                surface = nil
            case .idleEnd:
                idle = false
                surface = nil
            case .trackingStopped:
                paused = true
                idle = false
                surface = nil
            case .appActivated, .browserDomain, .heartbeat:
                paused = false
                surface = event
            }
            let end = index + 1 < ordered.count ? ordered[index + 1].timestamp : now
            guard end > event.timestamp else { continue }
            if idle && !paused {
                result.append(TimelineBlock(start: event.timestamp, end: end, label: "Idle / away", category: .neutral,
                    detail: "No input or Mac asleep", kind: .idle))
            } else if !paused, let surface {
                let observedEnd = min(end, surface.timestamp.addingTimeInterval(configuration.maximumObservedGap))
                if observedEnd > event.timestamp {
                    result.append(TimelineBlock(start: event.timestamp, end: observedEnd,
                        label: resolver.displayName(for: surface), category: resolver.category(for: surface),
                        detail: surface.windowTitle))
                }
                if observedEnd < end {
                    result.append(unobserved(start: max(event.timestamp, observedEnd), end: end))
                }
            } else {
                result.append(unobserved(start: event.timestamp, end: end))
            }
        }
        return result
    }

    private func priority(_ kind: ActivityKind) -> Int {
        switch kind {
        case .idleEnd: 0
        case .appActivated: 1
        case .heartbeat: 2
        case .browserDomain: 3
        case .idleStart: 4
        case .trackingStopped: 5
        }
    }

    private func unobserved(start: Date, end: Date) -> TimelineBlock {
        TimelineBlock(start: start, end: end, label: "Unobserved / away", category: .neutral,
            detail: "Tracking paused or no fresh activity signal", kind: .unobserved)
    }
}
