import Foundation
import LifeReplayCore
import OSLog
import SwiftData

@MainActor
final class LifeReplayStore {
    private let logger = Logger(subsystem: "LifeReplayMac", category: "Store")
    private let container: ModelContainer
    private let context: ModelContext
    private(set) var lastError: String?
    private var cachedSeeds: [AppCategorySeed]?

    init() throws {
        // Preserve legacy entity names for existing local stores. HealthSnapshot
        // is schema compatibility only; no companion or health collection exists.
        let schema = Schema([ActivityEvent.self, AppCategory.self, FocusSession.self,
                             DriftEvent.self, HealthSnapshot.self, DailyReplay.self, FocusSettings.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
        if try context.fetchCount(FetchDescriptor<AppCategory>()) == 0 {
            for seed in DefaultAppCategories.all { context.insert(AppCategory(seed: seed)) }
        }
        if try context.fetchCount(FetchDescriptor<FocusSettings>()) == 0 {
            context.insert(FocusSettings(core: CoreFocusSettings()))
        }
        try context.save()
    }

    @discardableResult
    func record(_ event: CoreActivityEvent) -> Bool {
        context.insert(ActivityEvent(core: event))
        do {
            try context.save()
            lastError = nil
            return true
        } catch {
            lastError = "Activity could not be saved: \(error.localizedDescription)"
            logger.error("\(self.lastError ?? "Store error", privacy: .public)")
            return false
        }
    }

    func report(for date: Date, now: Date = Date()) -> (report: WorkdayReport, drifts: [CoreDriftEvent]) {
        guard let day = Calendar.current.dateInterval(of: .day, for: date) else {
            return (WorkdayReport(blocks: []), [])
        }
        let end = min(day.end, now)
        let events = eventsForDay(date, endingAt: end)
        let settings = focusSettings()
        let resolver = CategoryResolver(seeds: categorySeeds())
        let rawBlocks = ActivityTimelineEngine(configuration: .init(
            maximumObservedGap: 30
        )).blocks(from: events, resolver: resolver, now: end)
        var focusConfiguration = settings.focusEngineConfiguration
        focusConfiguration.maximumObservedGap = 30
        let analysis = FocusEngine(configuration: focusConfiguration, resolver: resolver)
            .analyze(events: events, now: end)
        return (WorkdayReport(blocks: rawBlocks, interval: DateInterval(start: day.start, end: end)),
                analysis.driftEvents.filter { $0.timestamp >= day.start })
    }

    private func eventsForDay(_ date: Date, endingAt end: Date) -> [CoreActivityEvent] {
        let start = Calendar.current.startOfDay(for: date)
        let predicate = #Predicate<ActivityEvent> { $0.timestamp >= start && $0.timestamp <= end }
        do {
            var events = try context.fetch(FetchDescriptor<ActivityEvent>(predicate: predicate,
                sortBy: [SortDescriptor(\ActivityEvent.timestamp)])).map(\.coreValue)
            // Carry state across midnight only when it is still supported. This
            // handles an idle Mac and uninterrupted work without charging a stale
            // last app to the next morning.
            let priorPredicate = #Predicate<ActivityEvent> { $0.timestamp < start }
            var prior = FetchDescriptor<ActivityEvent>(predicate: priorPredicate,
                sortBy: [SortDescriptor(\ActivityEvent.timestamp, order: .reverse)])
            prior.fetchLimit = 1
            if let previous = try context.fetch(prior).first?.coreValue {
                let fresh = start.timeIntervalSince(previous.timestamp) < 30
                if previous.kind == .idleStart || previous.kind == .trackingStopped || fresh {
                    // Keep the old observation's expiry, rather than extending it
                    // by another observation-gap allowance at midnight.
                    let carry = CoreActivityEvent(timestamp: previous.timestamp, kind: previous.kind,
                        appBundleID: previous.appBundleID, appName: previous.appName,
                        windowTitle: previous.windowTitle, browserDomain: previous.browserDomain)
                    events.insert(carry, at: 0)
                }
            }
            // Clip the pre-midnight carry at the report boundary by inserting no
            // artificial heartbeat; the engine maintains the original expiry.
            return events
        } catch {
            lastError = "Could not read activity: \(error.localizedDescription)"
            logger.error("\(self.lastError ?? "Store error", privacy: .public)")
            return []
        }
    }

    func categories() -> [CoreAppCategory] {
        do {
            return try context.fetch(FetchDescriptor<AppCategory>(sortBy: [SortDescriptor(\AppCategory.displayName)])).map(\.coreValue)
        } catch {
            lastError = "Could not read categories: \(error.localizedDescription)"
            return []
        }
    }

    private func categorySeeds() -> [AppCategorySeed] {
        if let cachedSeeds { return cachedSeeds }
        let seeds = categories().map { AppCategorySeed($0.matchPattern, $0.displayName, $0.category) }
        cachedSeeds = seeds
        return seeds
    }

    func replaceCategories(with seeds: [AppCategorySeed]) throws {
        for category in try context.fetch(FetchDescriptor<AppCategory>()) { context.delete(category) }
        for seed in seeds { context.insert(AppCategory(seed: seed, isUserEdited: true)) }
        do {
            try context.save()
            cachedSeeds = nil
            lastError = nil
        } catch {
            context.rollback()
            throw error
        }
    }

    func focusSettings() -> CoreFocusSettings {
        do {
            var descriptor = FetchDescriptor<FocusSettings>()
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first?.coreValue ?? CoreFocusSettings()
        } catch {
            lastError = "Could not read tracking settings: \(error.localizedDescription)"
            return CoreFocusSettings()
        }
    }

    func updateIdleThreshold(_ seconds: Double) throws {
        guard seconds.isFinite, (30...900).contains(seconds) else { return }
        var descriptor = FetchDescriptor<FocusSettings>()
        descriptor.fetchLimit = 1
        guard let settings = try context.fetch(descriptor).first else { return }
        settings.idleThresholdSeconds = seconds
        do { try context.save() } catch { context.rollback(); throw error }
    }

    func exportCSV(for date: Date, to url: URL) throws {
        let report = report(for: date).report
        func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let rows = report.blocks.map {
            [$0.start.ISO8601Format(), $0.end.ISO8601Format(), $0.label, $0.category.rawValue,
             $0.kind.rawValue, String($0.end.timeIntervalSince($0.start))].map(quoted).joined(separator: ",")
        }
        try (["start,end,activity,category,evidence,seconds"] + rows).joined(separator: "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }
}
