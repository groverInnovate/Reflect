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
        timelineBlocks(from: sessions, events: events, resolver: .init(), now: now)
    }

    public func timelineBlocks(
        from sessions: [FocusSession],
        events: [ActivityEvent],
        resolver: CategoryResolver,
        now: Date = Date()
    ) -> [TimelineBlock] {
        let idleIntervals = idleIntervals(from: events, now: now)
        let activeBlocks = eventTimelineBlocks(from: events, idleIntervals: idleIntervals, resolver: resolver, now: now)
        let sessionBlocks = activeBlocks.isEmpty ? sessionBlocks(from: sessions, excluding: idleIntervals) : activeBlocks
        let idleBlocks = idleTimelineBlocks(from: idleIntervals)
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

    private func sessionBlocks(
        from sessions: [FocusSession],
        excluding idleIntervals: [(start: Date, end: Date)]
    ) -> [TimelineBlock] {
        sessions
            .flatMap { session -> [TimelineBlock] in
                guard let end = session.end, end > session.start else { return [] }
                return activeIntervals(from: session.start, to: end, excluding: idleIntervals).map { interval in
                    TimelineBlock(
                        start: interval.start,
                        end: interval.end,
                        label: session.primaryAppName ?? label(for: session.category),
                        category: session.category,
                        detail: nil
                    )
                }
            }
            .sorted { $0.start < $1.start }
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

    private func eventTimelineBlocks(
        from events: [ActivityEvent],
        idleIntervals: [(start: Date, end: Date)],
        resolver: CategoryResolver,
        now: Date
    ) -> [TimelineBlock] {
        let meaningfulEvents = events
            .filter { $0.kind == .appActivated || $0.kind == .browserDomain }
            .sorted { $0.timestamp < $1.timestamp }
        guard !meaningfulEvents.isEmpty else { return [] }

        return meaningfulEvents.enumerated().flatMap { index, event -> [TimelineBlock] in
            let nextTimestamp = meaningfulEvents.dropFirst(index + 1).first?.timestamp ?? now
            guard nextTimestamp > event.timestamp else { return [] }

            return activeIntervals(from: event.timestamp, to: nextTimestamp, excluding: idleIntervals).map { interval in
                TimelineBlock(
                    start: interval.start,
                    end: interval.end,
                    label: resolver.displayName(for: event),
                    category: resolver.category(for: event),
                    detail: event.windowTitle
                )
            }
        }
        .sorted { $0.start < $1.start }
    }

    private func idleIntervals(from events: [ActivityEvent], now: Date) -> [(start: Date, end: Date)] {
        let ordered = events.sorted { $0.timestamp < $1.timestamp }
        var idleStart: Date?
        var intervals: [(start: Date, end: Date)] = []

        for event in ordered {
            switch event.kind {
            case .idleStart:
                idleStart = event.timestamp
            case .idleEnd:
                if let start = idleStart, event.timestamp > start {
                    intervals.append((start, event.timestamp))
                }
                idleStart = nil
            case .appActivated, .browserDomain:
                continue
            }
        }

        if let start = idleStart, now > start {
            intervals.append((start, now))
        }

        return intervals
    }

    private func idleTimelineBlocks(from intervals: [(start: Date, end: Date)]) -> [TimelineBlock] {
        intervals.map { interval in
            TimelineBlock(
                start: interval.start,
                end: interval.end,
                label: "Idle period",
                category: .neutral,
                detail: "No keyboard or mouse input"
            )
        }
    }

    private func mergeBlocks(_ sortedBlocks: [TimelineBlock]) -> [TimelineBlock] {
        sortedBlocks.reduce(into: [TimelineBlock]()) { blocks, next in
            guard var previous = blocks.last else {
                blocks.append(next)
                return
            }

            let gap = next.start.timeIntervalSince(previous.end)
            let overlaps = next.start < previous.end
            if previous.category == next.category, previous.label == next.label, gap <= configuration.mergeGap, !overlaps {
                previous.end = max(previous.end, next.end)
                if let detail = next.detail, previous.detail != detail {
                    previous.detail = [previous.detail, detail].compactMap(\.self).joined(separator: ", ")
                }
                blocks[blocks.count - 1] = previous
            } else {
                blocks.append(next)
            }
        }
    }

    public func fallbackSummary(blocks: [TimelineBlock], driftEvents: [DriftEvent], focusScore: Int) -> String {
        insightReport(blocks: blocks, driftEvents: driftEvents, focusScore: focusScore).journalSummary
    }

    public func insightReport(blocks: [TimelineBlock], driftEvents: [DriftEvent], focusScore: Int) -> DailyInsightReport {
        let productiveMinutes = minutes(for: .productive, in: blocks)
        let distractingMinutes = minutes(for: .distracting, in: blocks)
        let idleMinutes = blocks
            .filter { $0.label == "Idle period" }
            .reduce(0) { $0 + minutes(in: $1) }
        let neutralMinutes = max(0, minutes(for: .neutral, in: blocks) - idleMinutes)
        let totalMinutes = blocks.reduce(0) { $0 + minutes(in: $1) }

        let productiveBlocks = blocks.filter { $0.category == .productive }
        let longest = productiveBlocks.max {
            $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start)
        }
        let worstDrift = driftEvents.max { $0.severity < $1.severity }
        let topDistractions = topDistractionNames(blocks: blocks, driftEvents: driftEvents)
        let studyMinutes = studyLikeMinutes(in: blocks)
        let codingMinutes = codingLikeMinutes(in: blocks)
        let deepWorkMinutes = deepWorkMinutes(in: blocks)
        let fragmentedProductiveMinutes = fragmentedProductiveMinutes(in: blocks)
        let topProductiveLabels = topLabels(for: .productive, in: blocks)
        let topActivities = activityBreakdown(from: blocks)
        let dataQualityWarnings = dataQualityWarnings(blocks: blocks)
        let calibrationSuggestions = calibrationSuggestions(
            totalMinutes: totalMinutes,
            productiveMinutes: productiveMinutes,
            studyMinutes: studyMinutes,
            distractingMinutes: distractingMinutes,
            neutralMinutes: neutralMinutes,
            idleMinutes: idleMinutes,
            topActivities: topActivities,
            dataQualityWarnings: dataQualityWarnings
        )
        let observations = observations(
            focusScore: focusScore,
            productiveMinutes: productiveMinutes,
            studyMinutes: studyMinutes,
            codingMinutes: codingMinutes,
            deepWorkMinutes: deepWorkMinutes,
            fragmentedProductiveMinutes: fragmentedProductiveMinutes,
            distractingMinutes: distractingMinutes,
            idleMinutes: idleMinutes,
            totalMinutes: totalMinutes,
            driftEvents: driftEvents,
            longestProductiveBlock: longest,
            topDistractions: topDistractions,
            topProductiveLabels: topProductiveLabels
        )
        let nextAction = nextAction(
            productiveMinutes: productiveMinutes,
            deepWorkMinutes: deepWorkMinutes,
            distractingMinutes: distractingMinutes,
            driftEvents: driftEvents,
            topDistractions: topDistractions
        )

        let summary = journalSummary(
            focusScore: focusScore,
            productiveMinutes: productiveMinutes,
            studyMinutes: studyMinutes,
            codingMinutes: codingMinutes,
            distractingMinutes: distractingMinutes,
            idleMinutes: idleMinutes,
            driftCount: driftEvents.count,
            longestProductiveBlock: longest,
            topDistractions: topDistractions,
            nextAction: nextAction
        )

        return DailyInsightReport(
            totalTrackedMinutes: totalMinutes,
            productiveMinutes: productiveMinutes,
            studyLikeMinutes: studyMinutes,
            codingLikeMinutes: codingMinutes,
            deepWorkMinutes: deepWorkMinutes,
            fragmentedProductiveMinutes: fragmentedProductiveMinutes,
            distractingMinutes: distractingMinutes,
            neutralMinutes: neutralMinutes,
            idleMinutes: idleMinutes,
            focusScore: focusScore,
            driftCount: driftEvents.count,
            longestProductiveBlockLabel: longest?.label,
            longestProductiveBlockMinutes: longest.map(minutes(in:)),
            worstDriftTrigger: worstDrift?.triggerAppNames.joined(separator: ", "),
            topActivities: topActivities,
            topProductiveLabels: topProductiveLabels,
            topDistractions: topDistractions,
            dataQualityWarnings: dataQualityWarnings,
            calibrationSuggestions: calibrationSuggestions,
            observations: observations,
            nextAction: nextAction,
            journalSummary: summary
        )
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

    private func minutes(for category: FocusCategory, in blocks: [TimelineBlock]) -> Int {
        blocks
            .filter { $0.category == category }
            .reduce(0) { $0 + minutes(in: $1) }
    }

    private func minutes(in block: TimelineBlock) -> Int {
        max(0, Int(block.end.timeIntervalSince(block.start) / 60))
    }

    private func studyLikeMinutes(in blocks: [TimelineBlock]) -> Int {
        blocks.enumerated().reduce(0) { total, indexedBlock in
            let index = indexedBlock.offset
            let block = indexedBlock.element
            guard block.category == .productive else {
                return total
            }
            guard isStudyLike(block) || isStudySupportBlock(block, at: index, in: blocks) else { return total }
            return total + minutes(in: block)
        }
    }

    private func isStudyLike(_ block: TimelineBlock) -> Bool {
        let studyTerms = [
            "obsidian", "notion", "hackmd", "reading", "lecture", "study", "pdf", "book",
            "books", "rust-book", "rust book", "research", "paper", "notes", "course", "docs"
        ]
        let label = block.label.lowercased()
        let detail = block.detail?.lowercased() ?? ""
        return studyTerms.contains { label.contains($0) || detail.contains($0) }
    }

    private func isStudySupportBlock(_ block: TimelineBlock, at index: Int, in blocks: [TimelineBlock]) -> Bool {
        let supportTerms = ["claude", "chatgpt", "anthropic", "openai"]
        let label = block.label.lowercased()
        let detail = block.detail?.lowercased() ?? ""
        guard supportTerms.contains(where: { label.contains($0) || detail.contains($0) }) else { return false }

        let window: TimeInterval = 5 * 60
        let neighbors = [
            index > 0 ? blocks[index - 1] : nil,
            index + 1 < blocks.count ? blocks[index + 1] : nil,
        ].compactMap(\.self)

        return neighbors.contains { neighbor in
            guard neighbor.category == .productive, isStudyLike(neighbor) else { return false }
            let gapBefore = max(0, block.start.timeIntervalSince(neighbor.end))
            let gapAfter = max(0, neighbor.start.timeIntervalSince(block.end))
            return min(gapBefore, gapAfter) <= window
        }
    }

    private func codingLikeMinutes(in blocks: [TimelineBlock]) -> Int {
        let codingTerms = [
            "vs code", "xcode", "terminal", "iterm", "github", "localhost", "cargo", "rust",
            "foundry", "hardhat", "noir", "nargo", "postman", "bruno", "solidity"
        ]
        return blocks.reduce(0) { total, block in
            let label = block.label.lowercased()
            let detail = block.detail?.lowercased() ?? ""
            guard block.category == .productive, codingTerms.contains(where: { label.contains($0) || detail.contains($0) }) else {
                return total
            }
            return total + minutes(in: block)
        }
    }

    private func deepWorkMinutes(in blocks: [TimelineBlock]) -> Int {
        blocks.reduce(0) { total, block in
            let duration = minutes(in: block)
            guard block.category == .productive, duration >= 45 else { return total }
            return total + duration
        }
    }

    private func fragmentedProductiveMinutes(in blocks: [TimelineBlock]) -> Int {
        blocks.reduce(0) { total, block in
            let duration = minutes(in: block)
            guard block.category == .productive, duration > 0, duration < 25 else { return total }
            return total + duration
        }
    }

    private func topDistractionNames(blocks: [TimelineBlock], driftEvents: [DriftEvent]) -> [String] {
        var counts: [String: Int] = [:]
        for block in blocks where block.category == .distracting {
            counts[block.label, default: 0] += minutes(in: block)
        }
        for drift in driftEvents {
            for trigger in drift.triggerAppNames {
                counts[trigger, default: 0] += 1
            }
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(3)
            .map(\.key)
    }

    private func topLabels(for category: FocusCategory, in blocks: [TimelineBlock]) -> [String] {
        var counts: [String: Int] = [:]
        for block in blocks where block.category == category {
            counts[block.label, default: 0] += minutes(in: block)
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(3)
            .map(\.key)
    }

    private func activityBreakdown(from blocks: [TimelineBlock]) -> [ActivityBreakdownItem] {
        var totals: [String: (label: String, category: FocusCategory, minutes: Int)] = [:]

        for block in blocks {
            let duration = minutes(in: block)
            guard duration > 0 else { continue }

            let key = "\(block.category.rawValue)|\(block.label.lowercased())"
            if let existing = totals[key] {
                totals[key] = (
                    label: existing.label,
                    category: existing.category,
                    minutes: existing.minutes + duration
                )
            } else {
                totals[key] = (label: block.label, category: block.category, minutes: duration)
            }
        }

        return totals.values
            .sorted { lhs, rhs in
                if lhs.minutes == rhs.minutes { return lhs.label < rhs.label }
                return lhs.minutes > rhs.minutes
            }
            .prefix(8)
            .map {
                ActivityBreakdownItem(label: $0.label, category: $0.category, minutes: $0.minutes)
            }
    }

    private func dataQualityWarnings(blocks: [TimelineBlock]) -> [String] {
        var warnings: [String] = []

        let longestActiveBlock = blocks
            .filter { $0.label != "Idle period" }
            .max { lhs, rhs in
                lhs.end.timeIntervalSince(lhs.start) < rhs.end.timeIntervalSince(rhs.start)
            }

        if let longestActiveBlock, minutes(in: longestActiveBlock) >= 6 * 60 {
            warnings.append(
                "\(longestActiveBlock.label) spans \(formatMinutes(minutes(in: longestActiveBlock))) without an idle split. If the Mac slept during that time, keep this build running so the new sleep-gap detector can correct it."
            )
        }

        let totalMinutes = blocks.reduce(0) { $0 + minutes(in: $1) }
        let idleMinutes = blocks
            .filter { $0.label == "Idle period" }
            .reduce(0) { $0 + minutes(in: $1) }
        if totalMinutes >= 8 * 60, idleMinutes == 0 {
            warnings.append("No idle/away time was recorded across a long tracked day; this may mean the app was not running through sleep/wake yet.")
        }

        return warnings
    }

    private func calibrationSuggestions(
        totalMinutes: Int,
        productiveMinutes: Int,
        studyMinutes: Int,
        distractingMinutes: Int,
        neutralMinutes: Int,
        idleMinutes: Int,
        topActivities: [ActivityBreakdownItem],
        dataQualityWarnings: [String]
    ) -> [String] {
        var suggestions: [String] = []
        let activeMinutes = max(0, totalMinutes - idleMinutes)

        if !dataQualityWarnings.isEmpty {
            suggestions.append("Run Repair Sleep Gaps before judging today's focus score.")
        }

        if activeMinutes > 0, Double(neutralMinutes) / Double(activeMinutes) >= 0.35 {
            let neutralLabels = topActivities
                .filter { $0.category == .neutral }
                .prefix(3)
                .map(\.label)
            let suffix = neutralLabels.isEmpty ? "" : " Start with: \(neutralLabels.joined(separator: ", "))."
            suggestions.append("A lot of active time is neutral/unclassified; edit categories to improve accuracy.\(suffix)")
        }

        if productiveMinutes >= 60, studyMinutes == 0 {
            suggestions.append("No study/research time was detected inside a productive day; add category rules for your lecture, PDF, course, or notes tools if that is wrong.")
        }

        if distractingMinutes == 0, activeMinutes >= 4 * 60 {
            suggestions.append("No distracting time was detected across a long active day; verify your distraction domains are categorized.")
        }

        return Array(suggestions.prefix(4))
    }

    private func observations(
        focusScore: Int,
        productiveMinutes: Int,
        studyMinutes: Int,
        codingMinutes: Int,
        deepWorkMinutes: Int,
        fragmentedProductiveMinutes: Int,
        distractingMinutes: Int,
        idleMinutes: Int,
        totalMinutes: Int,
        driftEvents: [DriftEvent],
        longestProductiveBlock: TimelineBlock?,
        topDistractions: [String],
        topProductiveLabels: [String]
    ) -> [String] {
        var insights: [String] = []

        if totalMinutes == 0 {
            return ["No meaningful activity was tracked yet; leave collection running during a real session."]
        }

        let productiveShare = Double(productiveMinutes) / Double(max(1, totalMinutes))
        let distractingShare = Double(distractingMinutes) / Double(max(1, totalMinutes))

        if let primary = topProductiveLabels.first, productiveMinutes > 0 {
            insights.append("The main productive thread was \(primary), accounting for the largest visible work block.")
        }

        if codingMinutes > 0, studyMinutes > 0 {
            insights.append("The day mixed \(formatMinutes(codingMinutes)) of coding-like work with \(formatMinutes(studyMinutes)) of study/research-like work.")
        } else if codingMinutes > 0 {
            insights.append("Most visible productive time looked coding/tooling-oriented: \(formatMinutes(codingMinutes)).")
        } else if studyMinutes > 0 {
            insights.append("Most visible productive time looked study/research-oriented: \(formatMinutes(studyMinutes)).")
        }

        if deepWorkMinutes >= 60 {
            insights.append("Deep-work time was meaningful at \(formatMinutes(deepWorkMinutes)) in productive blocks of at least 45 minutes.")
        } else if fragmentedProductiveMinutes >= 30 {
            insights.append("Productive time was fragmented: \(formatMinutes(fragmentedProductiveMinutes)) came from short blocks under 25 minutes.")
        }

        if productiveShare >= 0.65 {
            insights.append("Most tracked time was productive, which suggests the day had a strong work/study base.")
        } else if productiveShare < 0.35 {
            insights.append("Productive time was a minority of the tracked day; the biggest opportunity is protecting one longer work block.")
        }

        if distractingMinutes >= 30 || distractingShare >= 0.2 {
            let label = topDistractions.first.map { " The main visible pull was \($0)." } ?? ""
            insights.append("Distraction consumed \(formatMinutes(distractingMinutes)) of tracked time.\(label)")
        }

        if driftEvents.count >= 2 {
            insights.append("There were \(driftEvents.count) drift events, so attention broke repeatedly rather than just once.")
        } else if driftEvents.isEmpty, productiveMinutes >= 60 {
            insights.append("No drift events were detected during productive time, which is a good sign for sustained focus.")
        }

        if let longestProductiveBlock {
            let minutes = minutes(in: longestProductiveBlock)
            if minutes >= 90 {
                insights.append("The best deep-work block was \(longestProductiveBlock.label) for \(formatMinutes(minutes)).")
            } else if productiveMinutes >= 60 {
                insights.append("Productive time existed, but it was fragmented; the longest block was only \(formatMinutes(minutes)).")
            }
        }

        if idleMinutes >= 60 {
            insights.append("There was \(formatMinutes(idleMinutes)) of idle time; if that was intentional rest, it should be treated differently from distraction.")
        }

        if focusScore < 50 {
            insights.append("Focus score was low; tomorrow's target should be one protected session before opening distracting sites.")
        }

        return Array(insights.prefix(7))
    }

    private func journalSummary(
        focusScore: Int,
        productiveMinutes: Int,
        studyMinutes: Int,
        codingMinutes: Int,
        distractingMinutes: Int,
        idleMinutes: Int,
        driftCount: Int,
        longestProductiveBlock: TimelineBlock?,
        topDistractions: [String],
        nextAction: String
    ) -> String {
        let bestBlock = longestProductiveBlock.map {
            " Best block: \($0.label) for \(formatMinutes(minutes(in: $0)))."
        } ?? ""
        let studyText = studyMinutes > 0 ? " \(formatMinutes(studyMinutes)) looked study/research-related." : ""
        let codingText = codingMinutes > 0 ? " \(formatMinutes(codingMinutes)) looked coding/tooling-related." : ""
        let distractionText = distractingMinutes > 0
            ? " Distracting/wasted time was about \(formatMinutes(distractingMinutes))\(topDistractions.first.map { ", led by \($0)" } ?? "")."
            : " No explicit distracting block was detected."
        let driftText = driftCount == 0 ? " No focus drift was detected." : " Focus drift showed up \(driftCount) time\(driftCount == 1 ? "" : "s")."
        let idleText = idleMinutes > 0 ? " Idle/away time was \(formatMinutes(idleMinutes))." : ""

        return "You logged \(formatMinutes(productiveMinutes)) of productive time today.\(studyText)\(codingText)\(distractionText)\(driftText)\(bestBlock)\(idleText) Focus score: \(focusScore)/100. Next: \(nextAction)"
    }

    private func nextAction(
        productiveMinutes: Int,
        deepWorkMinutes: Int,
        distractingMinutes: Int,
        driftEvents: [DriftEvent],
        topDistractions: [String]
    ) -> String {
        if productiveMinutes == 0 {
            return "start with one 45-minute work or study block before opening distracting sites."
        }
        if distractingMinutes >= 45 || driftEvents.count >= 2 {
            let distraction = topDistractions.first ?? "the biggest distraction"
            return "keep \(distraction) closed until after the first protected work block."
        }
        if deepWorkMinutes < 60, productiveMinutes >= 60 {
            return "turn the useful work into one uninterrupted 60-minute block."
        }
        return "repeat the conditions around the best productive block."
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}

public struct ActivityBreakdownItem: Codable, Equatable, Sendable {
    public var label: String
    public var category: FocusCategory
    public var minutes: Int

    public init(label: String, category: FocusCategory, minutes: Int) {
        self.label = label
        self.category = category
        self.minutes = minutes
    }
}

public struct DailyInsightReport: Codable, Equatable, Sendable {
    public var totalTrackedMinutes: Int
    public var productiveMinutes: Int
    public var studyLikeMinutes: Int
    public var codingLikeMinutes: Int
    public var deepWorkMinutes: Int
    public var fragmentedProductiveMinutes: Int
    public var distractingMinutes: Int
    public var neutralMinutes: Int
    public var idleMinutes: Int
    public var focusScore: Int
    public var driftCount: Int
    public var longestProductiveBlockLabel: String?
    public var longestProductiveBlockMinutes: Int?
    public var worstDriftTrigger: String?
    public var topActivities: [ActivityBreakdownItem]
    public var topProductiveLabels: [String]
    public var topDistractions: [String]
    public var dataQualityWarnings: [String]
    public var calibrationSuggestions: [String]
    public var observations: [String]
    public var nextAction: String
    public var journalSummary: String
}
