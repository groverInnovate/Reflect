import Foundation

public struct ReplayEngineConfiguration: Sendable {
    public var maximumObservedGap: TimeInterval

    public init(maximumObservedGap: TimeInterval = 120) {
        self.maximumObservedGap = maximumObservedGap
    }
}

public struct ReplayEngine: Sendable {
    private let configuration: ReplayEngineConfiguration

    public init(configuration: ReplayEngineConfiguration = .init()) {
        self.configuration = configuration
    }

    public func timelineBlocks(from sessions: [FocusSession]) -> [TimelineBlock] {
        mergeBlocks(sessionBlocks(from: sessions))
    }

    public func timelineBlocks(from sessions: [FocusSession], events: [ActivityEvent], now: Date = Date()) -> [TimelineBlock] {
        timelineBlocks(from: sessions, events: events, resolver: .init(), now: now)
    }

    public func timelineBlocks(
        from sessions: [FocusSession],
        events: [ActivityEvent],
        resolver: CategoryResolver,
        now: Date = Date()
    ) -> [TimelineBlock] {
        let eventBlocks = ActivityTimelineEngine(
            configuration: ActivityTimelineConfiguration(
                maximumObservedGap: configuration.maximumObservedGap
            )
        ).blocks(from: events, resolver: resolver, now: now)

        // Events are the source of truth when present. Session blocks remain a
        // fallback for an old store that predates the raw event timeline.
        let hasMeaningfulEvent = events.contains {
            $0.kind == .appActivated || $0.kind == .browserDomain || $0.kind == .heartbeat
        }
        let fallbackBlocks = hasMeaningfulEvent
            ? []
            : sessionBlocks(from: sessions, excluding: idleIntervals(from: events, now: now))
        return mergeBlocks((fallbackBlocks + (hasMeaningfulEvent ? eventBlocks : eventBlocks.filter { $0.kind == .idle })).sorted { $0.start < $1.start })
    }

    private func sessionBlocks(from sessions: [FocusSession]) -> [TimelineBlock] {
        sessions
            .compactMap { session -> TimelineBlock? in
                guard let end = session.end, end > session.start else { return nil }
                return TimelineBlock(
                    start: session.start,
                    end: end,
                    label: session.primaryAppName ?? label(for: session.category),
                    category: session.category,
                    detail: nil,
                    kind: .observed
                )
            }
            .sorted { $0.start < $1.start }
    }

    private func sessionBlocks(
        from sessions: [FocusSession],
        excluding idleIntervals: [(start: Date, end: Date)]
    ) -> [TimelineBlock] {
        sessions.flatMap { session in
            guard let end = session.end, end > session.start else { return [TimelineBlock]() }
            return activeIntervals(from: session.start, to: end, excluding: idleIntervals).map {
                TimelineBlock(
                    start: $0.start,
                    end: $0.end,
                    label: session.primaryAppName ?? label(for: session.category),
                    category: session.category,
                    kind: .observed
                )
            }
        }
        .sorted { $0.start < $1.start }
    }

    private func idleIntervals(from events: [ActivityEvent], now: Date) -> [(start: Date, end: Date)] {
        var intervals: [(start: Date, end: Date)] = []
        var idleStart: Date?
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.kind {
            case .idleStart:
                idleStart = idleStart ?? event.timestamp
            case .idleEnd:
                if let idleStart, event.timestamp > idleStart {
                    intervals.append((idleStart, min(event.timestamp, now)))
                }
                idleStart = nil
            case .appActivated, .browserDomain, .heartbeat, .trackingStopped:
                continue
            }
        }
        if let idleStart, now > idleStart {
            intervals.append((idleStart, now))
        }
        return intervals.filter { $0.end > $0.start }
    }

    private func activeIntervals(
        from start: Date,
        to end: Date,
        excluding idleIntervals: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
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

    private func mergeBlocks(_ sortedBlocks: [TimelineBlock]) -> [TimelineBlock] {
        sortedBlocks.reduce(into: [TimelineBlock]()) { blocks, next in
            guard var previous = blocks.last else {
                blocks.append(next)
                return
            }

            let gap = next.start.timeIntervalSince(previous.end)
            let overlaps = next.start < previous.end
            let sameContext = previous.detail == next.detail
            if previous.kind == next.kind,
               previous.category == next.category,
               previous.label == next.label,
               sameContext,
               gap <= 0.001,
               !overlaps {
                previous.end = max(previous.end, next.end)
                blocks[blocks.count - 1] = previous
            } else {
                blocks.append(next)
            }
        }
    }

    public func encode(blocks: [TimelineBlock]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(blocks), as: UTF8.self)
    }

    public func decodeBlocks(from json: String) throws -> [TimelineBlock] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TimelineBlock].self, from: Data(json.utf8))
    }

    private func label(for category: FocusCategory) -> String {
        switch category {
        case .productive: "Work"
        case .neutral: "Other"
        case .distracting: "Distractions"
        }
    }
}
