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
        let sessionBlocks = sessionBlocks(from: sessions, events: events)
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

    private func sessionBlocks(from sessions: [FocusSession], events: [ActivityEvent]) -> [TimelineBlock] {
        sessions
            .compactMap { session -> TimelineBlock? in
                guard let end = session.end, end > session.start else { return nil }
                let sessionEvents = events.filter {
                    ($0.kind == .appActivated || $0.kind == .browserDomain)
                        && $0.timestamp >= session.start
                        && $0.timestamp <= end
                }
                let enriched = enrichedSessionText(for: session, events: sessionEvents)
                return TimelineBlock(
                    start: session.start,
                    end: end,
                    label: enriched.label,
                    category: session.category,
                    detail: enriched.detail
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
        let observations = observations(
            focusScore: focusScore,
            productiveMinutes: productiveMinutes,
            distractingMinutes: distractingMinutes,
            idleMinutes: idleMinutes,
            totalMinutes: totalMinutes,
            driftEvents: driftEvents,
            longestProductiveBlock: longest,
            topDistractions: topDistractions
        )
        let tomorrowTarget = tomorrowTarget(
            focusScore: focusScore,
            productiveMinutes: productiveMinutes,
            distractingMinutes: distractingMinutes,
            driftCount: driftEvents.count,
            longestProductiveBlock: longest,
            topDistractions: topDistractions
        )

        let summary = journalSummary(
            focusScore: focusScore,
            productiveMinutes: productiveMinutes,
            studyMinutes: studyMinutes,
            distractingMinutes: distractingMinutes,
            idleMinutes: idleMinutes,
            driftCount: driftEvents.count,
            longestProductiveBlock: longest,
            topDistractions: topDistractions
        )

        return DailyInsightReport(
            totalTrackedMinutes: totalMinutes,
            productiveMinutes: productiveMinutes,
            studyLikeMinutes: studyMinutes,
            distractingMinutes: distractingMinutes,
            neutralMinutes: neutralMinutes,
            idleMinutes: idleMinutes,
            focusScore: focusScore,
            driftCount: driftEvents.count,
            longestProductiveBlockLabel: longest?.label,
            longestProductiveBlockMinutes: longest.map(minutes(in:)),
            worstDriftTrigger: worstDrift?.triggerAppNames.joined(separator: ", "),
            topDistractions: topDistractions,
            observations: observations,
            tomorrowTarget: tomorrowTarget,
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

    private func enrichedSessionText(for session: FocusSession, events: [ActivityEvent]) -> (label: String, detail: String?) {
        let names = rankedNames(from: events)
        let primaryName = names.first ?? session.primaryAppName ?? label(for: session.category)
        let projectName = projectName(from: events)
        let domains = rankedDomains(from: events)
        let detailNames = Array(unique(names + domains).prefix(4))
        let detail = detailNames.dropFirst().isEmpty ? nil : detailNames.dropFirst().joined(separator: ", ")

        switch session.category {
        case .productive:
            if let projectName, isCodingTool(primaryName) || names.contains(where: isCodingTool) {
                return ("Coding - \(projectName)", detail)
            }
            if looksStudyLike(primaryName) || events.contains(where: { looksStudyLike($0.windowTitle ?? "") }) {
                return ("Study / research - \(primaryName)", detail)
            }
            if let domain = domains.first, isDocumentationDomain(domain) {
                return ("Docs / research - \(domain)", detail)
            }
            return (primaryName, detail)
        case .neutral:
            return (primaryName, detail)
        case .distracting:
            return ("Distraction - \(primaryName)", detail)
        }
    }

    private func rankedNames(from events: [ActivityEvent]) -> [String] {
        rankedValues(events.compactMap { event in
            if let domain = event.browserDomain, !domain.isEmpty {
                return domain
            }
            if let appName = event.appName, !appName.isEmpty {
                return appName
            }
            return event.appBundleID
        })
    }

    private func rankedDomains(from events: [ActivityEvent]) -> [String] {
        rankedValues(events.compactMap(\.browserDomain))
    }

    private func rankedValues(_ values: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            counts[cleaned, default: 0] += 1
        }
        return counts.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }.map(\.key)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            let key = value.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func projectName(from events: [ActivityEvent]) -> String? {
        let appNames = events.compactMap(\.appName).map { $0.lowercased() }
        let codingContext = appNames.contains { app in
            app.contains("code") || app.contains("xcode") || app.contains("terminal") || app.contains("iterm")
        }
        guard codingContext else { return nil }

        for title in events.compactMap(\.windowTitle) {
            if let project = projectName(fromWindowTitle: title) {
                return project
            }
        }
        return nil
    }

    private func projectName(fromWindowTitle title: String) -> String? {
        let separators = [" - ", " — ", " – ", " | "]
        for separator in separators {
            var parts = title
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            while let last = parts.last, isGenericWindowToken(last) {
                parts.removeLast()
            }
            guard parts.count >= 2 else { continue }
            if let candidate = parts.last, candidate.count >= 2, !looksLikeSourceFile(candidate) {
                return candidate
            }
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenericWindowToken(trimmed), trimmed.count <= 48 else {
            return nil
        }
        return trimmed
    }

    private func looksLikeSourceFile(_ token: String) -> Bool {
        let value = token.lowercased()
        return [".swift", ".rs", ".sol", ".js", ".ts", ".tsx", ".jsx", ".py", ".md", ".toml", ".json", ".yaml", ".yml"].contains {
            value.hasSuffix($0)
        }
    }

    private func isGenericWindowToken(_ token: String) -> Bool {
        let value = token.lowercased()
        return value.contains("visual studio code")
            || value == "code"
            || value == "xcode"
            || value == "terminal"
            || value == "iterm"
            || value == "brave browser"
            || value == "google chrome"
            || value == "safari"
    }

    private func isCodingTool(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.contains("code")
            || value.contains("xcode")
            || value.contains("terminal")
            || value.contains("iterm")
            || value.contains("cargo")
            || value.contains("rust")
            || value.contains("foundry")
            || value.contains("hardhat")
            || value.contains("noir")
    }

    private func looksStudyLike(_ text: String) -> Bool {
        let value = text.lowercased()
        return ["obsidian", "notion", "reading", "lecture", "study", "pdf", "book", "research", "paper", "notes"].contains {
            value.contains($0)
        }
    }

    private func isDocumentationDomain(_ domain: String) -> Bool {
        let value = domain.lowercased()
        return value.contains("docs.")
            || value.contains("developer.")
            || value.contains("documentation")
            || value.contains("github.com")
            || value.contains("stackoverflow.com")
            || value.contains("swift.org")
            || value.contains("rust-lang.org")
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
        let studyTerms = ["obsidian", "notion", "reading", "lecture", "study", "pdf", "books", "research"]
        return blocks.reduce(0) { total, block in
            let label = block.label.lowercased()
            let detail = block.detail?.lowercased() ?? ""
            guard block.category == .productive, studyTerms.contains(where: { label.contains($0) || detail.contains($0) }) else {
                return total
            }
            return total + minutes(in: block)
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

    private func observations(
        focusScore: Int,
        productiveMinutes: Int,
        distractingMinutes: Int,
        idleMinutes: Int,
        totalMinutes: Int,
        driftEvents: [DriftEvent],
        longestProductiveBlock: TimelineBlock?,
        topDistractions: [String]
    ) -> [String] {
        var insights: [String] = []

        if totalMinutes == 0 {
            return ["No meaningful activity was tracked yet; leave collection running during a real session."]
        }

        let productiveShare = Double(productiveMinutes) / Double(max(1, totalMinutes))
        let distractingShare = Double(distractingMinutes) / Double(max(1, totalMinutes))

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

        return Array(insights.prefix(5))
    }

    private func journalSummary(
        focusScore: Int,
        productiveMinutes: Int,
        studyMinutes: Int,
        distractingMinutes: Int,
        idleMinutes: Int,
        driftCount: Int,
        longestProductiveBlock: TimelineBlock?,
        topDistractions: [String]
    ) -> String {
        let bestBlock = longestProductiveBlock.map {
            " Best block: \($0.label) for \(formatMinutes(minutes(in: $0)))."
        } ?? ""
        let studyText = studyMinutes > 0 ? " \(formatMinutes(studyMinutes)) looked study/research-related." : ""
        let distractionText = distractingMinutes > 0
            ? " Distracting/wasted time was about \(formatMinutes(distractingMinutes))\(topDistractions.first.map { ", led by \($0)" } ?? "")."
            : " No explicit distracting block was detected."
        let driftText = driftCount == 0 ? " No focus drift was detected." : " Focus drift showed up \(driftCount) time\(driftCount == 1 ? "" : "s")."
        let idleText = idleMinutes > 0 ? " Idle/away time was \(formatMinutes(idleMinutes))." : ""

        return "You logged \(formatMinutes(productiveMinutes)) of productive time today.\(studyText)\(distractionText)\(driftText)\(bestBlock)\(idleText) Focus score: \(focusScore)/100."
    }

    private func tomorrowTarget(
        focusScore: Int,
        productiveMinutes: Int,
        distractingMinutes: Int,
        driftCount: Int,
        longestProductiveBlock: TimelineBlock?,
        topDistractions: [String]
    ) -> String {
        if productiveMinutes == 0 {
            return "Start with one 45-minute tracked work/study block before opening communication or entertainment apps."
        }

        if distractingMinutes >= 45 || driftCount >= 2 {
            let distraction = topDistractions.first ?? "the biggest distraction"
            return "Protect the first deep-work block from \(distraction); open it only after one planned work/study session is complete."
        }

        if let longestProductiveBlock, minutes(in: longestProductiveBlock) < 60, productiveMinutes >= 60 {
            return "Turn fragmented work into one uninterrupted 60-minute block before optimizing anything else."
        }

        if focusScore >= 80, let longestProductiveBlock {
            return "Repeat the conditions around \(longestProductiveBlock.label); that was the strongest pattern in today's data."
        }

        return "Aim for one protected 90-minute productive block and check whether drift stays at zero during that window."
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

public struct DailyInsightReport: Codable, Equatable, Sendable {
    public var totalTrackedMinutes: Int
    public var productiveMinutes: Int
    public var studyLikeMinutes: Int
    public var distractingMinutes: Int
    public var neutralMinutes: Int
    public var idleMinutes: Int
    public var focusScore: Int
    public var driftCount: Int
    public var longestProductiveBlockLabel: String?
    public var longestProductiveBlockMinutes: Int?
    public var worstDriftTrigger: String?
    public var topDistractions: [String]
    public var observations: [String]
    public var tomorrowTarget: String
    public var journalSummary: String
}
