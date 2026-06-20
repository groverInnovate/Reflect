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
        let analysis = FocusEngine().analyze(events: events, now: now)
        let newDrifts = analysis.driftEvents.filter { !existingDriftKeys.contains(driftKey($0)) }

        replaceTodaySessionsAndDrifts(with: analysis, now: now)
        return (analysis, newDrifts)
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
