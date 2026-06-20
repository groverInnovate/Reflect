import Foundation
import LifeReplayCore
import OSLog
import SwiftData

private struct ReplaySnapshot {
    var analysis: FocusAnalysis
    var blocks: [TimelineBlock]
    var fallbackSummary: String
}

struct DataStatus {
    var todayEvents: Int
    var todaySessions: Int
    var todayDrifts: Int
    var allEvents: Int
    var allSessions: Int
    var allDrifts: Int
    var allReplays: Int
    var latestReplayGeneratedAt: Date?
}

struct WeeklyRollup {
    var days: Int
    var averageFocusScore: Int
    var bestDay: DailyReplay?
    var latestDays: [DailyReplay]
}

private struct ConfigurationExport: Codable {
    var exportedAt: Date
    var categories: [CategoryExport]
    var focusSettings: FocusSettingsExport
}

private struct CategoryExport: Codable {
    var matchPattern: String
    var displayName: String
    var category: String
    var isUserEdited: Bool
}

private struct FocusSettingsExport: Codable {
    var idleThresholdSeconds: Double
    var sessionMinimumDurationSeconds: Double
    var driftWindowMinutes: Double
    var baselineSwitchesPerHour: Double
    var productiveSessionMinimumMinutes: Double
}

@MainActor
final class LifeReplayStore {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "Store")
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        let schema = Schema([
            ActivityEvent.self,
            AppCategory.self,
            FocusSession.self,
            DriftEvent.self,
            HealthSnapshot.self,
            DailyReplay.self,
            FocusSettings.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        try seedDefaultCategoriesIfNeeded()
        try seedFocusSettingsIfNeeded()
    }

    func record(_ event: ActivityEvent) {
        context.insert(event)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save activity event: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshTodayAnalysis(now: Date = Date()) -> (analysis: FocusAnalysis, newDrifts: [DriftEvent]) {
        let existingDriftKeys = Set(driftEventsForToday(now: now).map(driftKey))
        let events = eventsForToday(now: now)
        let analysis = makeFocusEngine().analyze(events: events, now: now)
        let newDrifts = analysis.driftEvents.filter { !existingDriftKeys.contains(driftKey($0)) }

        replaceTodaySessionsAndDrifts(with: analysis, now: now)
        return (analysis, newDrifts)
    }

    func generateDailyReplay(now: Date = Date()) -> DailyReplay? {
        generateDailyReplaySnapshot(now: now, narrative: nil, usedOnDeviceAI: false)
    }

    func generateDailyReplayWithNarrative(now: Date = Date()) async -> DailyReplay? {
        let snapshot = replaySnapshot(now: now)
        let narrative = await OnDeviceNarrativeService().generate(
            blocks: snapshot.blocks,
            driftEvents: snapshot.analysis.driftEvents,
            focusScore: snapshot.analysis.focusScore,
            fallback: snapshot.fallbackSummary
        )
        return generateDailyReplaySnapshot(
            now: now,
            narrative: narrative.summary,
            usedOnDeviceAI: narrative.usedOnDeviceAI,
            snapshot: snapshot
        )
    }

    private func replaySnapshot(now: Date) -> ReplaySnapshot {
        let events = eventsForToday(now: now)
        let analysis = makeFocusEngine().analyze(events: events, now: now)
        let replayEngine = ReplayEngine()
        let blocks = replayEngine.timelineBlocks(from: analysis.sessions, events: events, now: now)
        let fallbackSummary = replayEngine.fallbackSummary(
            blocks: blocks,
            driftEvents: analysis.driftEvents,
            focusScore: analysis.focusScore
        )
        return ReplaySnapshot(analysis: analysis, blocks: blocks, fallbackSummary: fallbackSummary)
    }

    private func generateDailyReplaySnapshot(
        now: Date,
        narrative: String?,
        usedOnDeviceAI: Bool,
        snapshot providedSnapshot: ReplaySnapshot? = nil
    ) -> DailyReplay? {
        let snapshot = providedSnapshot ?? replaySnapshot(now: now)
        let replayEngine = ReplayEngine()
        do {
            let json = try replayEngine.encode(blocks: snapshot.blocks)
            let existingReplay = existingDailyReplay(for: now)
            let replay = existingReplay ?? DailyReplay(
                date: Calendar.current.startOfDay(for: now),
                timelineBlocksJSON: json,
                focusScore: snapshot.analysis.focusScore
            )
            replay.timelineBlocksJSON = json
            replay.focusScore = snapshot.analysis.focusScore
            replay.narrativeSummary = narrative ?? snapshot.fallbackSummary
            replay.generatedAt = Date()
            replay.usedOnDeviceAI = usedOnDeviceAI

            if existingReplay == nil {
                context.insert(replay)
            }
            try context.save()
            return replay
        } catch {
            logger.error("Failed to generate daily replay: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func eventsForToday(now: Date = Date()) -> [ActivityEvent] {
        let interval = Calendar.current.dateInterval(of: .day, for: now)
        let start = interval?.start ?? now
        let end = interval?.end ?? now
        let predicate = #Predicate<ActivityEvent> { event in
            event.timestamp >= start && event.timestamp < end
        }
        var descriptor = FetchDescriptor<ActivityEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\ActivityEvent.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 2_000

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch today's activity events: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func categories() -> [AppCategory] {
        let descriptor = FetchDescriptor<AppCategory>(
            sortBy: [SortDescriptor(\AppCategory.displayName, order: .forward)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch app categories: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func dataStatus(now: Date = Date()) -> DataStatus {
        DataStatus(
            todayEvents: eventsForToday(now: now).count,
            todaySessions: focusSessionsForToday(now: now).count,
            todayDrifts: driftEventsForToday(now: now).count,
            allEvents: count(ActivityEvent.self),
            allSessions: count(FocusSession.self),
            allDrifts: count(DriftEvent.self),
            allReplays: count(DailyReplay.self),
            latestReplayGeneratedAt: latestDailyReplay()?.generatedAt
        )
    }

    func existingDailyReplay(for date: Date = Date()) -> DailyReplay? {
        let day = Calendar.current.startOfDay(for: date)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? date
        let predicate = #Predicate<DailyReplay> { replay in
            replay.date >= day && replay.date < nextDay
        }
        var descriptor = FetchDescriptor<DailyReplay>(
            predicate: predicate,
            sortBy: [SortDescriptor(\DailyReplay.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch daily replay: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func dailyReplays(limit: Int = 60) -> [DailyReplay] {
        var descriptor = FetchDescriptor<DailyReplay>(
            sortBy: [SortDescriptor(\DailyReplay.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch daily replay history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func weeklyRollup(now: Date = Date()) -> WeeklyRollup {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let predicate = #Predicate<DailyReplay> { replay in
            replay.date >= start && replay.date <= now
        }
        let descriptor = FetchDescriptor<DailyReplay>(
            predicate: predicate,
            sortBy: [SortDescriptor(\DailyReplay.date, order: .reverse)]
        )

        let replays: [DailyReplay]
        do {
            replays = try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch weekly rollup: \(error.localizedDescription, privacy: .public)")
            replays = []
        }

        let average = replays.isEmpty
            ? 0
            : Int((Double(replays.reduce(0) { $0 + $1.focusScore }) / Double(replays.count)).rounded())
        let best = replays.max { $0.focusScore < $1.focusScore }
        return WeeklyRollup(days: replays.count, averageFocusScore: average, bestDay: best, latestDays: replays)
    }

    private func latestDailyReplay() -> DailyReplay? {
        var descriptor = FetchDescriptor<DailyReplay>(
            sortBy: [SortDescriptor(\DailyReplay.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch latest daily replay: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func markdownForDailyReplay(_ replay: DailyReplay) -> String {
        let replayEngine = ReplayEngine()
        let blocks = (try? replayEngine.decodeBlocks(from: replay.timelineBlocksJSON)) ?? []
        var lines: [String] = [
            "# Life Replay - \(replay.date.formatted(date: .long, time: .omitted))",
            "",
            "Focus Score: \(replay.focusScore)/100",
            "Generated: \(replay.generatedAt.formatted(date: .abbreviated, time: .shortened))",
            "On-device AI: \(replay.usedOnDeviceAI ? "yes" : "no")",
            "",
            "## Summary",
            "",
            replay.narrativeSummary ?? "No summary generated.",
            "",
            "## Timeline",
            "",
        ]

        if blocks.isEmpty {
            lines.append("No timeline blocks.")
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            for block in blocks {
                let start = formatter.string(from: block.start)
                let end = formatter.string(from: block.end)
                let minutes = Int(block.end.timeIntervalSince(block.start) / 60)
                lines.append("- \(start)-\(end): \(block.label) (\(minutes)m, \(block.category.rawValue))")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    func exportTodayDebugData(to folderURL: URL, now: Date = Date()) throws {
        let events = eventsForToday(now: now)
        let analysis = makeFocusEngine().analyze(events: events, now: now)
        let day = Calendar.current.startOfDay(for: now).formatted(.iso8601.year().month().day())

        try csvForActivityEvents(events).write(
            to: folderURL.appendingPathComponent("life-replay-events-\(day).csv"),
            atomically: true,
            encoding: .utf8
        )
        try csvForDriftEvents(analysis.driftEvents).write(
            to: folderURL.appendingPathComponent("life-replay-drifts-\(day).csv"),
            atomically: true,
            encoding: .utf8
        )
    }

    func exportConfiguration(to url: URL) throws {
        let settings = focusSettings()
        let export = ConfigurationExport(
            exportedAt: Date(),
            categories: categories().map {
                CategoryExport(
                    matchPattern: $0.matchPattern,
                    displayName: $0.displayName,
                    category: $0.category.rawValue,
                    isUserEdited: $0.isUserEdited
                )
            },
            focusSettings: FocusSettingsExport(
                idleThresholdSeconds: settings.idleThresholdSeconds,
                sessionMinimumDurationSeconds: settings.sessionMinimumDurationSeconds,
                driftWindowMinutes: settings.driftWindowMinutes,
                baselineSwitchesPerHour: settings.baselineSwitchesPerHour,
                productiveSessionMinimumMinutes: settings.productiveSessionMinimumMinutes
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        try data.write(to: url, options: .atomic)
    }

    func categorySeeds() -> [AppCategorySeed] {
        categories().map {
            AppCategorySeed($0.matchPattern, $0.displayName, $0.category)
        }
    }

    func makeFocusEngine() -> FocusEngine {
        FocusEngine(
            configuration: focusSettings().focusEngineConfiguration,
            resolver: CategoryResolver(seeds: categorySeeds())
        )
    }

    func focusSettings() -> FocusSettings {
        var descriptor = FetchDescriptor<FocusSettings>()
        descriptor.fetchLimit = 1
        do {
            if let settings = try context.fetch(descriptor).first {
                return settings
            }
        } catch {
            logger.error("Failed to fetch focus settings: \(error.localizedDescription, privacy: .public)")
        }

        let settings = FocusSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    func updateFocusSettings(
        idleThresholdSeconds: Double,
        sessionMinimumDurationSeconds: Double,
        driftWindowMinutes: Double,
        baselineSwitchesPerHour: Double,
        productiveSessionMinimumMinutes: Double
    ) {
        let settings = focusSettings()
        settings.idleThresholdSeconds = idleThresholdSeconds
        settings.sessionMinimumDurationSeconds = sessionMinimumDurationSeconds
        settings.driftWindowMinutes = driftWindowMinutes
        settings.baselineSwitchesPerHour = baselineSwitchesPerHour
        settings.productiveSessionMinimumMinutes = productiveSessionMinimumMinutes

        do {
            try context.save()
            _ = refreshTodayAnalysis()
        } catch {
            logger.error("Failed to save focus settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    func replaceCategories(with seeds: [AppCategorySeed]) {
        for category in categories() {
            context.delete(category)
        }
        for seed in seeds {
            context.insert(AppCategory(
                matchPattern: seed.matchPattern,
                displayName: seed.displayName,
                category: seed.category,
                isUserEdited: true
            ))
        }

        do {
            try context.save()
            _ = refreshTodayAnalysis()
        } catch {
            logger.error("Failed to replace app categories: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func driftEventsForToday(now: Date = Date()) -> [DriftEvent] {
        let interval = Calendar.current.dateInterval(of: .day, for: now)
        let start = interval?.start ?? now
        let end = interval?.end ?? now
        let predicate = #Predicate<DriftEvent> { event in
            event.timestamp >= start && event.timestamp < end
        }
        let descriptor = FetchDescriptor<DriftEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\DriftEvent.timestamp, order: .forward)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch today's drift events: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func focusSessionsForToday(now: Date = Date()) -> [FocusSession] {
        let interval = Calendar.current.dateInterval(of: .day, for: now)
        let start = interval?.start ?? now
        let end = interval?.end ?? now
        let predicate = #Predicate<FocusSession> { session in
            session.start >= start && session.start < end
        }
        let descriptor = FetchDescriptor<FocusSession>(predicate: predicate)

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch today's focus sessions: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func replaceTodaySessionsAndDrifts(with analysis: FocusAnalysis, now: Date) {
        for session in focusSessionsForToday(now: now) {
            context.delete(session)
        }
        for drift in driftEventsForToday(now: now) {
            context.delete(drift)
        }
        for session in analysis.sessions {
            context.insert(session)
        }
        for drift in analysis.driftEvents {
            context.insert(drift)
        }

        do {
            try context.save()
        } catch {
            logger.error("Failed to save refreshed focus analysis: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func count<T: PersistentModel>(_ modelType: T.Type) -> Int {
        do {
            let descriptor = FetchDescriptor<T>()
            return try context.fetchCount(descriptor)
        } catch {
            logger.error("Failed to count \(String(describing: modelType), privacy: .public): \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    private func driftKey(_ event: DriftEvent) -> String {
        let triggerKey = event.triggerAppNames.sorted().joined(separator: "|")
        return "\(Int(event.timestamp.timeIntervalSince1970))-\(event.switchCountInWindow)-\(triggerKey)"
    }

    private func csvForActivityEvents(_ events: [ActivityEvent]) -> String {
        var rows = ["timestamp,kind,appBundleID,appName,windowTitle,browserDomain,source"]
        rows += events.map {
            [
                $0.timestamp.ISO8601Format(),
                $0.kind.rawValue,
                $0.appBundleID ?? "",
                $0.appName ?? "",
                $0.windowTitle ?? "",
                $0.browserDomain ?? "",
                $0.source,
            ].map(csvEscape).joined(separator: ",")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func csvForDriftEvents(_ drifts: [DriftEvent]) -> String {
        var rows = ["timestamp,triggerAppNames,switchCountInWindow,baselineSwitchRate,severity"]
        rows += drifts.map {
            [
                $0.timestamp.ISO8601Format(),
                $0.triggerAppNames.joined(separator: "; "),
                String($0.switchCountInWindow),
                String($0.baselineSwitchRate),
                String($0.severity),
            ].map(csvEscape).joined(separator: ",")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func seedDefaultCategoriesIfNeeded() throws {
        var descriptor = FetchDescriptor<AppCategory>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }

        for seed in DefaultAppCategories.all {
            context.insert(AppCategory(
                matchPattern: seed.matchPattern,
                displayName: seed.displayName,
                category: seed.category
            ))
        }
        try context.save()
        logger.info("Seeded \(DefaultAppCategories.all.count) default app categories")
    }

    private func seedFocusSettingsIfNeeded() throws {
        var descriptor = FetchDescriptor<FocusSettings>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(FocusSettings())
        try context.save()
        logger.info("Seeded default focus settings")
    }
}
