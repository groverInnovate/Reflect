import Foundation

public final class ActivityEvent {
    public var timestamp: Date
    public var kindRawValue: String
    public var appBundleID: String?
    public var appName: String?
    public var windowTitle: String?
    public var browserDomain: String?
    public var source: String

    public var kind: ActivityKind {
        get { ActivityKind(rawValue: kindRawValue) ?? .appActivated }
        set { kindRawValue = newValue.rawValue }
    }

    public init(
        timestamp: Date,
        kind: ActivityKind,
        appBundleID: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        browserDomain: String? = nil,
        source: String = "mac"
    ) {
        self.timestamp = timestamp
        self.kindRawValue = kind.rawValue
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.browserDomain = browserDomain
        self.source = source
    }
}

public enum ActivityKind: String, Codable, Sendable {
    case appActivated
    case idleStart
    case idleEnd
    case browserDomain
    /// A periodic proof that the frontmost surface is still visible and active.
    /// State-change events alone cannot tell the difference between a user who
    /// stayed in an app and an app that stopped being observed for an hour.
    case heartbeat
}

public final class AppCategory {
    public var matchPattern: String
    public var displayName: String
    public var categoryRawValue: String
    public var isUserEdited: Bool

    public var category: FocusCategory {
        get { FocusCategory(rawValue: categoryRawValue) ?? .neutral }
        set { categoryRawValue = newValue.rawValue }
    }

    public init(
        matchPattern: String,
        displayName: String,
        category: FocusCategory,
        isUserEdited: Bool = false
    ) {
        self.matchPattern = matchPattern
        self.displayName = displayName
        self.categoryRawValue = category.rawValue
        self.isUserEdited = isUserEdited
    }
}

public enum FocusCategory: String, Codable, Sendable {
    case productive
    case neutral
    case distracting
}

public final class FocusSession {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var categoryRawValue: String
    public var primaryAppName: String?
    public var switchCount: Int
    public var idleSeconds: Int

    public var category: FocusCategory {
        get { FocusCategory(rawValue: categoryRawValue) ?? .neutral }
        set { categoryRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date? = nil,
        category: FocusCategory,
        primaryAppName: String? = nil,
        switchCount: Int = 0,
        idleSeconds: Int = 0
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.categoryRawValue = category.rawValue
        self.primaryAppName = primaryAppName
        self.switchCount = switchCount
        self.idleSeconds = idleSeconds
    }
}

public final class DriftEvent {
    public var timestamp: Date
    public var precedingSessionID: UUID?
    public var triggerAppNames: [String]
    public var switchCountInWindow: Int
    public var baselineSwitchRate: Double
    public var severity: Double

    public init(
        timestamp: Date,
        precedingSessionID: UUID? = nil,
        triggerAppNames: [String] = [],
        switchCountInWindow: Int,
        baselineSwitchRate: Double,
        severity: Double
    ) {
        self.timestamp = timestamp
        self.precedingSessionID = precedingSessionID
        self.triggerAppNames = triggerAppNames
        self.switchCountInWindow = switchCountInWindow
        self.baselineSwitchRate = baselineSwitchRate
        self.severity = severity
    }
}

public final class HealthSnapshot {
    public var date: Date
    public var avgHeartRate: Double?
    public var hrv: Double?
    public var steps: Int?
    public var sleepHours: Double?
    public var workoutSummary: String?
    public var sourceFramework: String

    public init(date: Date, sourceFramework: String) {
        self.date = date
        self.sourceFramework = sourceFramework
    }
}

public final class DailyReplay {
    public var date: Date
    public var timelineBlocksJSON: String
    public var focusScore: Int
    public var narrativeSummary: String?
    public var generatedAt: Date
    public var usedOnDeviceAI: Bool

    public init(
        date: Date,
        timelineBlocksJSON: String,
        focusScore: Int,
        narrativeSummary: String? = nil,
        generatedAt: Date = Date(),
        usedOnDeviceAI: Bool = false
    ) {
        self.date = date
        self.timelineBlocksJSON = timelineBlocksJSON
        self.focusScore = focusScore
        self.narrativeSummary = narrativeSummary
        self.generatedAt = generatedAt
        self.usedOnDeviceAI = usedOnDeviceAI
    }
}

public final class FocusSettings {
    public var idleThresholdSeconds: Double
    public var sessionMinimumDurationSeconds: Double
    public var driftWindowMinutes: Double
    public var baselineSwitchesPerHour: Double
    public var productiveSessionMinimumMinutes: Double
    public var maximumObservationGapSeconds: Double

    public init(
        idleThresholdSeconds: Double = 90,
        sessionMinimumDurationSeconds: Double = 90,
        driftWindowMinutes: Double = 10,
        baselineSwitchesPerHour: Double = 12,
        productiveSessionMinimumMinutes: Double = 5,
        maximumObservationGapSeconds: Double = 120
    ) {
        self.idleThresholdSeconds = idleThresholdSeconds
        self.sessionMinimumDurationSeconds = sessionMinimumDurationSeconds
        self.driftWindowMinutes = driftWindowMinutes
        self.baselineSwitchesPerHour = baselineSwitchesPerHour
        self.productiveSessionMinimumMinutes = productiveSessionMinimumMinutes
        self.maximumObservationGapSeconds = maximumObservationGapSeconds
    }

    public var focusEngineConfiguration: FocusEngineConfiguration {
        FocusEngineConfiguration(
            idleThresholdSeconds: idleThresholdSeconds,
            sessionMinimumDuration: sessionMinimumDurationSeconds,
            driftWindow: driftWindowMinutes * 60,
            defaultBaselineSwitchesPerHour: baselineSwitchesPerHour,
            productiveSessionMinimumDuration: productiveSessionMinimumMinutes * 60,
            maximumObservedGap: maximumObservationGapSeconds
        )
    }
}

public enum TimelineBlockKind: String, Codable, Sendable {
    case observed
    case idle
    case unobserved
}

public struct TimelineBlock: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var label: String
    public var category: FocusCategory
    public var detail: String?
    public var kind: TimelineBlockKind

    public init(
        start: Date,
        end: Date,
        label: String,
        category: FocusCategory,
        detail: String? = nil,
        kind: TimelineBlockKind = .observed
    ) {
        self.start = start
        self.end = end
        self.label = label
        self.category = category
        self.detail = detail
        if kind == .observed && (label == "Idle period" || label == "Idle / away") {
            self.kind = .idle
        } else {
            self.kind = kind
        }
    }

    private enum CodingKeys: String, CodingKey {
        case start, end, label, category, detail, kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        label = try container.decode(String.self, forKey: .label)
        category = try container.decode(FocusCategory.self, forKey: .category)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        // Replays generated before observation quality was modeled remain readable.
        if let decodedKind = try container.decodeIfPresent(TimelineBlockKind.self, forKey: .kind) {
            kind = decodedKind
        } else if label == "Idle period" || label == "Idle / away" {
            kind = .idle
        } else {
            kind = .observed
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(label, forKey: .label)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encode(kind, forKey: .kind)
    }
}
