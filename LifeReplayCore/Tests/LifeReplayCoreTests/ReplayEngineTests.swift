import Foundation
import Testing
@testable import LifeReplayCore

@Suite("Replay engine")
struct ReplayEngineTests {
    @Test("keeps adjacent blocks with different labels separate")
    func keepsDifferentLabelsSeparate() {
        let start = Date(timeIntervalSince1970: 0)
        let sessions = [
            FocusSession(start: start, end: start.addingTimeInterval(600), category: .productive, primaryAppName: "VS Code"),
            FocusSession(start: start.addingTimeInterval(700), end: start.addingTimeInterval(1200), category: .productive, primaryAppName: "Terminal"),
            FocusSession(start: start.addingTimeInterval(1500), end: start.addingTimeInterval(1800), category: .neutral, primaryAppName: "Mail"),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: sessions)

        #expect(blocks.count == 3)
        #expect(blocks[0].category == .productive)
        #expect(blocks[0].label == "VS Code")
        #expect(blocks[1].label == "Terminal")
    }

    @Test("fallback summary names longest productive block")
    func fallbackSummaryUsesLongestBlock() {
        let start = Date(timeIntervalSince1970: 0)
        let blocks = [
            TimelineBlock(start: start, end: start.addingTimeInterval(600), label: "Mail", category: .neutral),
            TimelineBlock(start: start.addingTimeInterval(900), end: start.addingTimeInterval(3900), label: "VS Code", category: .productive),
        ]

        let summary = ReplayEngine().fallbackSummary(blocks: blocks, driftEvents: [], focusScore: 82)

        #expect(summary.contains("VS Code"))
        #expect(summary.contains("50m"))
        #expect(summary.contains("82"))
    }

    @Test("timeline blocks round-trip through JSON")
    func timelineBlocksRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let blocks = [
            TimelineBlock(
                start: start,
                end: start.addingTimeInterval(600),
                label: "VS Code",
                category: .productive,
                detail: "Terminal"
            ),
        ]
        let engine = ReplayEngine()

        let json = try engine.encode(blocks: blocks)
        let decoded = try engine.decodeBlocks(from: json)

        #expect(decoded == blocks)
    }

    @Test("idle events appear as timeline blocks")
    func idleEventsAppearAsTimelineBlocks() {
        let start = Date(timeIntervalSince1970: 0)
        let sessions = [
            FocusSession(start: start, end: start.addingTimeInterval(600), category: .productive, primaryAppName: "VS Code"),
        ]
        let events = [
            ActivityEvent(timestamp: start.addingTimeInterval(900), kind: .idleStart),
            ActivityEvent(timestamp: start.addingTimeInterval(1_200), kind: .idleEnd),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: sessions, events: events, now: start.addingTimeInterval(1_500))

        #expect(blocks.contains { $0.label == "Idle / away" && $0.kind == .idle && $0.start == start.addingTimeInterval(900) })
    }

    @Test("idle time is not double counted inside productive timeline blocks")
    func idleTimeIsSubtractedFromSessionBlocks() {
        let start = Date(timeIntervalSince1970: 0)
        let sessions = [
            FocusSession(start: start, end: start.addingTimeInterval(1_800), category: .productive, primaryAppName: "VS Code"),
        ]
        let events = [
            ActivityEvent(timestamp: start.addingTimeInterval(600), kind: .idleStart),
            ActivityEvent(timestamp: start.addingTimeInterval(1_200), kind: .idleEnd),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: sessions, events: events, now: start.addingTimeInterval(1_800))
        let productiveMinutes = blocks
            .filter { $0.category == .productive }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        let idleMinutes = blocks
            .filter { $0.kind == .idle }
            .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }

        #expect(blocks.count == 3)
        #expect(productiveMinutes == 20)
        #expect(idleMinutes == 10)
    }

    @Test("browser domain intervals are allocated by observed active tab")
    func browserDomainIntervalsUseObservedActiveTab() {
        let start = Date(timeIntervalSince1970: 0)
        let sessions = [
            FocusSession(start: start, end: start.addingTimeInterval(89 * 60), category: .neutral, primaryAppName: "chatgpt.com"),
        ]
        let events = [
            ActivityEvent(timestamp: start, kind: .browserDomain, browserDomain: "chatgpt.com"),
        ] + stride(from: 60, to: 15 * 60, by: 60).map {
            ActivityEvent(timestamp: start.addingTimeInterval(TimeInterval($0)), kind: .heartbeat, browserDomain: "chatgpt.com")
        } + [
            ActivityEvent(timestamp: start.addingTimeInterval(15 * 60), kind: .browserDomain, browserDomain: "rust-book.cs.brown.edu"),
        ] + stride(from: 16 * 60, to: 89 * 60, by: 60).map {
            ActivityEvent(timestamp: start.addingTimeInterval(TimeInterval($0)), kind: .heartbeat, browserDomain: "rust-book.cs.brown.edu")
        } + [
            ActivityEvent(timestamp: start.addingTimeInterval(89 * 60), kind: .idleStart),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: sessions, events: events, now: start.addingTimeInterval(89 * 60))

        #expect(blocks.contains(TimelineBlock(
            start: start,
            end: start.addingTimeInterval(15 * 60),
            label: "ChatGPT",
            category: .productive
        )))
        #expect(blocks.contains(TimelineBlock(
            start: start.addingTimeInterval(15 * 60),
            end: start.addingTimeInterval(89 * 60),
            label: "Rust Book",
            category: .productive
        )))
    }

    @Test("window-title changes remain separate task contexts")
    func windowTitleChangesRemainSeparateContexts() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [
            ActivityEvent(timestamp: start, kind: .appActivated, appBundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", windowTitle: "hive - main.rs"),
            ActivityEvent(timestamp: start.addingTimeInterval(60), kind: .heartbeat, appBundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", windowTitle: "hive - main.rs"),
            ActivityEvent(timestamp: start.addingTimeInterval(120), kind: .heartbeat, appBundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", windowTitle: "lean-sim - README.md"),
            ActivityEvent(timestamp: start.addingTimeInterval(180), kind: .heartbeat, appBundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", windowTitle: "lean-sim - README.md"),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: [], events: events, now: start.addingTimeInterval(240))

        #expect(blocks.count == 2)
        #expect(blocks[0].detail == "hive - main.rs")
        #expect(blocks[1].detail == "lean-sim - README.md")
        #expect(blocks.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) } == 4)
    }

    @Test("does not assign a long silent gap to the previous app")
    func longSilentGapBecomesUnobserved() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [
            ActivityEvent(timestamp: start, kind: .appActivated, appBundleID: "com.microsoft.VSCode", appName: "VS Code"),
        ]

        let blocks = ReplayEngine().timelineBlocks(
            from: [],
            events: events,
            now: start.addingTimeInterval(60 * 60)
        )

        #expect(blocks.contains { $0.kind == .observed && $0.label == "VS Code" && $0.end.timeIntervalSince($0.start) == 120 })
        #expect(blocks.contains { $0.kind == .unobserved && $0.label == "Unobserved / away" })
        let report = ReplayEngine().insightReport(blocks: blocks, driftEvents: [], focusScore: 90)
        #expect(report.productiveMinutes == 2)
        #expect(report.unobservedMinutes == 58)
        #expect(report.journalSummary.contains("unobserved"))
        #expect(report.nextAction.contains("fix collection"))
    }

    @Test("insight report turns timeline blocks into journal metrics")
    func insightReportBuildsJournalMetrics() {
        let start = Date(timeIntervalSince1970: 0)
        let blocks = [
            TimelineBlock(
                start: start,
                end: start.addingTimeInterval(3_600),
                label: "Research reading",
                category: .productive,
                detail: "PDF notes"
            ),
            TimelineBlock(
                start: start.addingTimeInterval(4_900),
                end: start.addingTimeInterval(5_500),
                label: "VS Code",
                category: .productive,
                detail: "Terminal"
            ),
            TimelineBlock(
                start: start.addingTimeInterval(5_700),
                end: start.addingTimeInterval(6_600),
                label: "Twitter",
                category: .distracting
            ),
            TimelineBlock(
                start: start.addingTimeInterval(6_900),
                end: start.addingTimeInterval(7_800),
                label: "Idle period",
                category: .neutral,
                detail: "No keyboard or mouse input"
            ),
        ]
        let drifts = [
            DriftEvent(
                timestamp: start.addingTimeInterval(5_800),
                triggerAppNames: ["Twitter"],
                switchCountInWindow: 8,
                baselineSwitchRate: 12,
                severity: 0.7
            ),
        ]

        let report = ReplayEngine().insightReport(blocks: blocks, driftEvents: drifts, focusScore: 74)

        #expect(report.productiveMinutes == 70)
        #expect(report.studyLikeMinutes == 60)
        #expect(report.codingLikeMinutes == 10)
        #expect(report.deepWorkMinutes == 60)
        #expect(report.fragmentedProductiveMinutes == 10)
        #expect(report.distractingMinutes == 15)
        #expect(report.idleMinutes == 15)
        #expect(report.neutralMinutes == 0)
        #expect(report.driftCount == 1)
        #expect(report.longestProductiveBlockLabel == "Research reading")
        #expect(report.topActivities.first == ActivityBreakdownItem(label: "Research reading", category: .productive, minutes: 60))
        #expect(report.topActivities.contains(ActivityBreakdownItem(label: "Twitter", category: .distracting, minutes: 15)))
        #expect(report.topProductiveLabels.first == "Research reading")
        #expect(report.topDistractions.first == "Twitter")
        #expect(!report.nextAction.isEmpty)
        #expect(report.journalSummary.contains("productive"))
        #expect(report.journalSummary.contains("Distracting/wasted"))
    }

    @Test("insight report warns about suspiciously long active blocks")
    func insightReportWarnsAboutLongUnsplitBlocks() {
        let start = Date(timeIntervalSince1970: 0)
        let blocks = [
            TimelineBlock(
                start: start,
                end: start.addingTimeInterval(7 * 3_600),
                label: "VS Code",
                category: .productive
            ),
        ]

        let report = ReplayEngine().insightReport(blocks: blocks, driftEvents: [], focusScore: 90)

        #expect(report.dataQualityWarnings.contains { $0.contains("VS Code") })
    }

    @Test("insight report suggests category calibration for high neutral time")
    func insightReportSuggestsCategoryCalibration() {
        let start = Date(timeIntervalSince1970: 0)
        let blocks = [
            TimelineBlock(
                start: start,
                end: start.addingTimeInterval(90 * 60),
                label: "Unknown Research Tool",
                category: .neutral
            ),
            TimelineBlock(
                start: start.addingTimeInterval(90 * 60),
                end: start.addingTimeInterval(120 * 60),
                label: "VS Code",
                category: .productive
            ),
        ]

        let report = ReplayEngine().insightReport(blocks: blocks, driftEvents: [], focusScore: 40)

        #expect(report.calibrationSuggestions.contains { $0.contains("edit categories") })
        #expect(report.calibrationSuggestions.contains { $0.contains("Unknown Research Tool") })
    }

    @Test("AI support near notes counts as study workflow")
    func aiSupportNearNotesCountsAsStudyWorkflow() {
        let start = Date(timeIntervalSince1970: 0)
        let blocks = [
            TimelineBlock(
                start: start,
                end: start.addingTimeInterval(20 * 60),
                label: "HackMD",
                category: .productive
            ),
            TimelineBlock(
                start: start.addingTimeInterval(20 * 60),
                end: start.addingTimeInterval(25 * 60),
                label: "Claude",
                category: .productive
            ),
            TimelineBlock(
                start: start.addingTimeInterval(25 * 60),
                end: start.addingTimeInterval(45 * 60),
                label: "HackMD",
                category: .productive
            ),
        ]

        let report = ReplayEngine().insightReport(blocks: blocks, driftEvents: [], focusScore: 80)

        #expect(report.productiveMinutes == 45)
        #expect(report.studyLikeMinutes == 45)
    }
}
