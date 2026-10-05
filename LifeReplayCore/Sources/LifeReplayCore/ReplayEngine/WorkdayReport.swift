import Foundation

/// All accounting stays in seconds. Formatting/rounding belongs at the display
/// boundary, so twenty short visits cannot disappear from the day's totals.
public struct WorkdayActivity: Identifiable, Sendable {
    public var id: String { "\(label)|\(category.rawValue)" }
    public var label: String
    public var category: FocusCategory
    public var seconds: TimeInterval
}

public struct WorkdayHour: Identifiable, Sendable {
    public var id: Date { start }
    public var start: Date
    public var productive: TimeInterval = 0
    public var neutral: TimeInterval = 0
    public var distracting: TimeInterval = 0
    public var active: TimeInterval { productive + neutral + distracting }
}

public struct WorkdayReport: Sendable {
    public var blocks: [TimelineBlock]
    public var activities: [WorkdayActivity]
    public var hours: [WorkdayHour]
    public var activeSeconds: TimeInterval
    public var productiveSeconds: TimeInterval
    public var neutralSeconds: TimeInterval
    public var distractingSeconds: TimeInterval
    public var idleSeconds: TimeInterval
    public var unobservedSeconds: TimeInterval

    public init(blocks input: [TimelineBlock], interval: DateInterval? = nil, calendar: Calendar = .current) {
        let blocks = input.compactMap { block -> TimelineBlock? in
            var clipped = block
            if let interval {
                clipped.start = max(interval.start, block.start)
                clipped.end = min(interval.end, block.end)
            }
            return clipped.end > clipped.start ? clipped : nil
        }
        var compacted: [TimelineBlock] = []
        for block in blocks.sorted(by: { $0.start < $1.start }) where block.end > block.start {
            if let last = compacted.last, last.kind == block.kind,
               last.category == block.category, last.label == block.label,
               abs(last.end.timeIntervalSince(block.start)) < 0.001 {
                compacted[compacted.count - 1].end = block.end
                if last.detail != block.detail { compacted[compacted.count - 1].detail = nil }
            } else { compacted.append(block) }
        }
        self.blocks = compacted
        var totals: [String: WorkdayActivity] = [:]
        var hourly: [Date: WorkdayHour] = [:]
        productiveSeconds = 0; neutralSeconds = 0; distractingSeconds = 0
        idleSeconds = 0; unobservedSeconds = 0
        for block in blocks {
            let seconds = max(0, block.end.timeIntervalSince(block.start))
            switch block.kind {
            case .idle: idleSeconds += seconds
            case .unobserved: unobservedSeconds += seconds
            case .observed:
                switch block.category {
                case .productive: productiveSeconds += seconds
                case .neutral: neutralSeconds += seconds
                case .distracting: distractingSeconds += seconds
                }
                let key = "\(block.label)|\(block.category.rawValue)"
                var entry = totals[key] ?? WorkdayActivity(label: block.label, category: block.category, seconds: 0)
                entry.seconds += seconds
                totals[key] = entry
                var cursor = block.start
                while cursor < block.end,
                      let hour = calendar.dateInterval(of: .hour, for: cursor) {
                    let end = min(hour.end, block.end)
                    let slice = end.timeIntervalSince(cursor)
                    var bucket = hourly[hour.start] ?? WorkdayHour(start: hour.start)
                    switch block.category {
                    case .productive: bucket.productive += slice
                    case .neutral: bucket.neutral += slice
                    case .distracting: bucket.distracting += slice
                    }
                    hourly[hour.start] = bucket
                    cursor = end
                }
            }
        }
        activeSeconds = productiveSeconds + neutralSeconds + distractingSeconds
        activities = totals.values.sorted {
            $0.seconds == $1.seconds ? $0.label < $1.label : $0.seconds > $1.seconds
        }
        // Include empty hours between observations so breaks remain visible.
        hours = []
        if let first = hourly.keys.min(), let last = hourly.keys.max() {
            var cursor = first
            while cursor <= last {
                hours.append(hourly[cursor] ?? WorkdayHour(start: cursor))
                guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
    }
}
