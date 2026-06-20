import Foundation
import LifeReplayCore
import OSLog
import SwiftData

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
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        try seedDefaultCategoriesIfNeeded()
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
        let events = eventsForToday(now: now)
        let analysis = makeFocusEngine().analyze(events: events, now: now)
        let replayEngine = ReplayEngine()
        let blocks = replayEngine.timelineBlocks(from: analysis.sessions)

        do {
            let json = try replayEngine.encode(blocks: blocks)
            let replay = existingDailyReplay(for: now) ?? DailyReplay(
                date: Calendar.current.startOfDay(for: now),
                timelineBlocksJSON: json,
                focusScore: analysis.focusScore
            )
            replay.timelineBlocksJSON = json
            replay.focusScore = analysis.focusScore
            replay.narrativeSummary = replayEngine.fallbackSummary(
                blocks: blocks,
                driftEvents: analysis.driftEvents,
                focusScore: analysis.focusScore
            )
            replay.generatedAt = Date()
            replay.usedOnDeviceAI = false

            if existingDailyReplay(for: now) == nil {
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

    func categorySeeds() -> [AppCategorySeed] {
        categories().map {
            AppCategorySeed($0.matchPattern, $0.displayName, $0.category)
        }
    }

    func makeFocusEngine() -> FocusEngine {
        FocusEngine(resolver: CategoryResolver(seeds: categorySeeds()))
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

    private func driftKey(_ event: DriftEvent) -> String {
        let triggerKey = event.triggerAppNames.sorted().joined(separator: "|")
        return "\(Int(event.timestamp.timeIntervalSince1970))-\(event.switchCountInWindow)-\(triggerKey)"
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
}
