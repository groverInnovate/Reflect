import Foundation
import LifeReplayCore
import SwiftData

// SwiftData belongs to the macOS persistence boundary. Keeping these records
// out of LifeReplayCore makes the timeline and scoring engines testable with
// the command-line Swift toolchain, without weakening the on-device store.

private typealias CoreActivityEvent = LifeReplayCore.ActivityEvent
private typealias CoreAppCategory = LifeReplayCore.AppCategory
private typealias CoreFocusSession = LifeReplayCore.FocusSession
private typealias CoreDriftEvent = LifeReplayCore.DriftEvent
private typealias CoreHealthSnapshot = LifeReplayCore.HealthSnapshot
private typealias CoreDailyReplay = LifeReplayCore.DailyReplay
private typealias CoreFocusSettings = LifeReplayCore.FocusSettings

@Model
final class ActivityEvent {
    var timestamp: Date
    var kindRawValue: String
    var appBundleID: String?
    var appName: String?
    var windowTitle: String?
    var browserDomain: String?
    var source: String

    init(core event: CoreActivityEvent) {
        timestamp = event.timestamp
        kindRawValue = event.kind.rawValue
        appBundleID = event.appBundleID
        appName = event.appName
        windowTitle = event.windowTitle
        browserDomain = event.browserDomain
        source = event.source
    }

    var coreValue: CoreActivityEvent {
        CoreActivityEvent(
            timestamp: timestamp,
            kind: ActivityKind(rawValue: kindRawValue) ?? .appActivated,
            appBundleID: appBundleID,
            appName: appName,
            windowTitle: windowTitle,
            browserDomain: browserDomain,
            source: source
        )
    }
}

@Model
final class AppCategory {
    var matchPattern: String
    var displayName: String
    var categoryRawValue: String
    var isUserEdited: Bool

    init(core category: CoreAppCategory) {
        matchPattern = category.matchPattern
        displayName = category.displayName
        categoryRawValue = category.category.rawValue
        isUserEdited = category.isUserEdited
    }

    init(seed: AppCategorySeed, isUserEdited: Bool = false) {
        matchPattern = seed.matchPattern
        displayName = seed.displayName
        categoryRawValue = seed.category.rawValue
        self.isUserEdited = isUserEdited
    }

    var coreValue: CoreAppCategory {
        CoreAppCategory(
            matchPattern: matchPattern,
            displayName: displayName,
            category: FocusCategory(rawValue: categoryRawValue) ?? .neutral,
            isUserEdited: isUserEdited
        )
    }
}

@Model
final class FocusSession {
    var id: UUID
    var start: Date
    var end: Date?
    var categoryRawValue: String
    var primaryAppName: String?
    var switchCount: Int
    var idleSeconds: Int

    init(core session: CoreFocusSession) {
        id = session.id
        start = session.start
        end = session.end
        categoryRawValue = session.category.rawValue
        primaryAppName = session.primaryAppName
        switchCount = session.switchCount
        idleSeconds = session.idleSeconds
    }

    var coreValue: CoreFocusSession {
        CoreFocusSession(
            id: id,
            start: start,
            end: end,
            category: FocusCategory(rawValue: categoryRawValue) ?? .neutral,
            primaryAppName: primaryAppName,
            switchCount: switchCount,
            idleSeconds: idleSeconds
        )
    }
}

@Model
final class DriftEvent {
    var timestamp: Date
    var precedingSessionID: UUID?
    var triggerAppNames: [String]
    var switchCountInWindow: Int
    var baselineSwitchRate: Double
    var severity: Double

    init(core drift: CoreDriftEvent) {
        timestamp = drift.timestamp
        precedingSessionID = drift.precedingSessionID
        triggerAppNames = drift.triggerAppNames
        switchCountInWindow = drift.switchCountInWindow
        baselineSwitchRate = drift.baselineSwitchRate
        severity = drift.severity
    }

    var coreValue: CoreDriftEvent {
        CoreDriftEvent(
            timestamp: timestamp,
            precedingSessionID: precedingSessionID,
            triggerAppNames: triggerAppNames,
            switchCountInWindow: switchCountInWindow,
            baselineSwitchRate: baselineSwitchRate,
            severity: severity
        )
    }
}

@Model
final class HealthSnapshot {
    var date: Date
    var avgHeartRate: Double?
    var hrv: Double?
    var steps: Int?
    var sleepHours: Double?
    var workoutSummary: String?
    var sourceFramework: String

    init(core snapshot: CoreHealthSnapshot) {
        date = snapshot.date
        avgHeartRate = snapshot.avgHeartRate
        hrv = snapshot.hrv
        steps = snapshot.steps
        sleepHours = snapshot.sleepHours
        workoutSummary = snapshot.workoutSummary
        sourceFramework = snapshot.sourceFramework
    }
}

@Model
final class DailyReplay {
    var date: Date
    var timelineBlocksJSON: String
    var focusScore: Int
    var narrativeSummary: String?
    var generatedAt: Date
    var usedOnDeviceAI: Bool

    init(core replay: CoreDailyReplay) {
        date = replay.date
        timelineBlocksJSON = replay.timelineBlocksJSON
        focusScore = replay.focusScore
        narrativeSummary = replay.narrativeSummary
        generatedAt = replay.generatedAt
        usedOnDeviceAI = replay.usedOnDeviceAI
    }

    var coreValue: CoreDailyReplay {
        CoreDailyReplay(
            date: date,
            timelineBlocksJSON: timelineBlocksJSON,
            focusScore: focusScore,
            narrativeSummary: narrativeSummary,
            generatedAt: generatedAt,
            usedOnDeviceAI: usedOnDeviceAI
        )
    }
}

@Model
final class FocusSettings {
    var idleThresholdSeconds: Double
    var sessionMinimumDurationSeconds: Double
    var driftWindowMinutes: Double
    var baselineSwitchesPerHour: Double
    var productiveSessionMinimumMinutes: Double
    var maximumObservationGapSeconds: Double = 120

    init(core settings: CoreFocusSettings) {
        idleThresholdSeconds = settings.idleThresholdSeconds
        sessionMinimumDurationSeconds = settings.sessionMinimumDurationSeconds
        driftWindowMinutes = settings.driftWindowMinutes
        baselineSwitchesPerHour = settings.baselineSwitchesPerHour
        productiveSessionMinimumMinutes = settings.productiveSessionMinimumMinutes
        maximumObservationGapSeconds = settings.maximumObservationGapSeconds
    }

    var coreValue: CoreFocusSettings {
        CoreFocusSettings(
            idleThresholdSeconds: idleThresholdSeconds,
            sessionMinimumDurationSeconds: sessionMinimumDurationSeconds,
            driftWindowMinutes: driftWindowMinutes,
            baselineSwitchesPerHour: baselineSwitchesPerHour,
            productiveSessionMinimumMinutes: productiveSessionMinimumMinutes,
            maximumObservationGapSeconds: maximumObservationGapSeconds
        )
    }
}
