import Foundation

public struct ReplayEngineConfiguration: Sendable {
    public var mergeGap: TimeInterval

    public init(mergeGap: TimeInterval = 3 * 60) {
        self.mergeGap = mergeGap
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
        let sessionBlocks = sessionBlocks(from: sessions)
        let idleBlocks = idleTimelineBlocks(from: events, now: now)
        return mergeBlocks((sessionBlocks + idleBlocks).sorted { $0.start < $1.start })
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
                    detail: nil
                )
            }
            .sorted { $0.start < $1.start }
    }

    private func idleTimelineBlocks(from events: [ActivityEvent], now: Date) -> [TimelineBlock] {
        let ordered = events.sorted { $0.timestamp < $1.timestamp }
        var idleStart: Date?
        var blocks: [TimelineBlock] = []

        for event in ordered {
            switch event.kind {
            case .idleStart:
                idleStart = event.timestamp
            case .idleEnd:
                if let start = idleStart, event.timestamp > start {
                    blocks.append(TimelineBlock(
                        start: start,
                        end: event.timestamp,
                        label: "Idle period",
                        category: .neutral,
                        detail: "No keyboard or mouse input"
                    ))
                }
                idleStart = nil
            case .appActivated, .browserDomain:
                continue
            }
        }

        if let start = idleStart, now > start {
            blocks.append(TimelineBlock(
                start: start,
                end: now,
                label: "Idle period",
                category: .neutral,
                detail: "No keyboard or mouse input"
            ))
        }

        return blocks
    }

    private func mergeBlocks(_ sortedBlocks: [TimelineBlock]) -> [TimelineBlock] {
        sortedBlocks.reduce(into: [TimelineBlock]()) { blocks, next in
            guard var previous = blocks.last else {
                blocks.append(next)
                return
            }

            let gap = next.start.timeIntervalSince(previous.end)
            let overlaps = next.start < previous.end
            if previous.category == next.category, gap <= configuration.mergeGap, !overlaps {
                previous.end = max(previous.end, next.end)
                if !previous.label.contains(next.label) {
                    previous.detail = [previous.detail, next.label].compactMap(\.self).joined(separator: ", ")
                }
                blocks[blocks.count - 1] = previous
            } else {
                blocks.append(next)
            }
        }
    }

    public func fallbackSummary(blocks: [TimelineBlock], driftEvents: [DriftEvent], focusScore: Int) -> String {
        let productiveBlocks = blocks.filter { $0.category == .productive }
        let longest = productiveBlocks.max {
            $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start)
        }

        guard let longest else {
            return "Tracked \(blocks.count) blocks today with a focus score of \(focusScore), but no sustained productive block yet."
        }

        let minutes = Int(longest.end.timeIntervalSince(longest.start) / 60)
        let driftText = driftEvents.isEmpty ? "no drift events" : "\(driftEvents.count) drift event\(driftEvents.count == 1 ? "" : "s")"
        return "Best block: \(longest.label) for \(minutes)m, with \(driftText) and a focus score of \(focusScore)."
    }

    public func encode(blocks: [TimelineBlock]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(blocks)
        return String(decoding: data, as: UTF8.self)
    }

    public func decodeBlocks(from json: String) throws -> [TimelineBlock] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TimelineBlock].self, from: Data(json.utf8))
    }

    private func label(for category: FocusCategory) -> String {
        switch category {
        case .productive:
            "Productive work"
        case .neutral:
            "Neutral activity"
        case .distracting:
            "Distraction"
        }
    }
}
