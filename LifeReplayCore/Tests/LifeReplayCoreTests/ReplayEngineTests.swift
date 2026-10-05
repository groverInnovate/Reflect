import Foundation
import XCTest
@testable import LifeReplayCore

final class ReplayEngineTests: XCTestCase {
    // keeps adjacent blocks with different labels separate
    func testKeepsDifferentLabelsSeparate() {
        let start = Date(timeIntervalSince1970: 0)
        let sessions = [
            FocusSession(start: start, end: start.addingTimeInterval(600), category: .productive, primaryAppName: "VS Code"),
            FocusSession(start: start.addingTimeInterval(700), end: start.addingTimeInterval(1200), category: .productive, primaryAppName: "Terminal"),
            FocusSession(start: start.addingTimeInterval(1500), end: start.addingTimeInterval(1800), category: .neutral, primaryAppName: "Mail"),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: sessions)

        XCTAssertTrue(blocks.count == 3)
        XCTAssertTrue(blocks[0].category == .productive)
        XCTAssertTrue(blocks[0].label == "VS Code")
        XCTAssertTrue(blocks[1].label == "Terminal")
    }

    // fallback summary names longest productive block
    func testFallbackSummaryUsesLongestBlock() {
        let start = Date(timeIntervalSince1970: 0)
        let blocks = [
            TimelineBlock(start: start, end: start.addingTimeInterval(600), label: "Mail", category: .neutral),
            TimelineBlock(start: start.addingTimeInterval(900), end: start.addingTimeInterval(3900), label: "VS Code", category: .productive),
        ]

        let summary = ReplayEngine().fallbackSummary(blocks: blocks, driftEvents: [], focusScore: 82)

        XCTAssertTrue(summary.contains("VS Code"))
        XCTAssertTrue(summary.contains("50m"))
        XCTAssertTrue(summary.contains("82"))
    }

    // timeline blocks round-trip through JSON
    func testTimelineBlocksRoundTrip() throws {
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

        XCTAssertTrue(decoded == blocks)
    }

    // idle events appear as timeline blocks
    func testIdleEventsAppearAsTimelineBlocks() {
        let start = Date(timeIntervalSince1970: 0)
        let sessions = [
            FocusSession(start: start, end: start.addingTimeInterval(600), category: .productive, primaryAppName: "VS Code"),
        ]
        let events = [
            ActivityEvent(timestamp: start.addingTimeInterval(900), kind: .idleStart),
            ActivityEvent(timestamp: start.addingTimeInterval(1_200), kind: .idleEnd),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: sessions, events: events, now: start.addingTimeInterval(1_500))

        XCTAssertTrue(blocks.contains { $0.label == "Idle / away" && $0.kind == .idle && $0.start == start.addingTimeInterval(900) })
    }

    // idle time is not double counted inside productive timeline blocks
    func testIdleTimeIsSubtractedFromSessionBlocks() {
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

        XCTAssertTrue(blocks.count == 3)
        XCTAssertTrue(productiveMinutes == 20)
        XCTAssertTrue(idleMinutes == 10)
    }

    // browser domain intervals are allocated by observed active tab
    func testBrowserDomainIntervalsUseObservedActiveTab() {
        let start = Date(timeIntervalSince1970: 0)
        let sessions = [
            FocusSession(start: start, end: start.addingTimeInterval(89 * 60), category: .neutral, primaryAppName: "chatgpt.com"),
        ]
        var events: [ActivityEvent] = [
            ActivityEvent(timestamp: start, kind: .browserDomain, browserDomain: "chatgpt.com"),
        ]
        events += stride(from: 60, to: 15 * 60, by: 60).map {
            ActivityEvent(timestamp: start.addingTimeInterval(TimeInterval($0)), kind: .heartbeat, browserDomain: "chatgpt.com")
        }
        events += [
            ActivityEvent(timestamp: start.addingTimeInterval(15 * 60), kind: .browserDomain, browserDomain: "rust-book.cs.brown.edu"),
        ]
        events += stride(from: 16 * 60, to: 89 * 60, by: 60).map {
            ActivityEvent(timestamp: start.addingTimeInterval(TimeInterval($0)), kind: .heartbeat, browserDomain: "rust-book.cs.brown.edu")
        }
        events += [
            ActivityEvent(timestamp: start.addingTimeInterval(89 * 60), kind: .idleStart),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: sessions, events: events, now: start.addingTimeInterval(89 * 60))

        XCTAssertTrue(blocks.contains(TimelineBlock(
            start: start,
            end: start.addingTimeInterval(15 * 60),
            label: "ChatGPT",
            category: .productive
        )))
        XCTAssertTrue(blocks.contains(TimelineBlock(
            start: start.addingTimeInterval(15 * 60),
            end: start.addingTimeInterval(89 * 60),
            label: "Rust Book",
            category: .productive
        )))
    }

    // window-title changes remain separate task contexts
    func testWindowTitleChangesRemainSeparateContexts() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [
            ActivityEvent(timestamp: start, kind: .appActivated, appBundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", windowTitle: "hive - main.rs"),
            ActivityEvent(timestamp: start.addingTimeInterval(60), kind: .heartbeat, appBundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", windowTitle: "hive - main.rs"),
            ActivityEvent(timestamp: start.addingTimeInterval(120), kind: .heartbeat, appBundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", windowTitle: "lean-sim - README.md"),
            ActivityEvent(timestamp: start.addingTimeInterval(180), kind: .heartbeat, appBundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", windowTitle: "lean-sim - README.md"),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: [], events: events, now: start.addingTimeInterval(240))

        XCTAssertTrue(blocks.count == 2)
        XCTAssertTrue(blocks[0].detail == "hive - main.rs")
        XCTAssertTrue(blocks[1].detail == "lean-sim - README.md")
        XCTAssertTrue(blocks.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) } == 4)
    }

    // does not assign a long silent gap to the previous app
    func testLongSilentGapBecomesUnobserved() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [
            ActivityEvent(timestamp: start, kind: .appActivated, appBundleID: "com.microsoft.VSCode", appName: "VS Code"),
        ]

        let blocks = ReplayEngine().timelineBlocks(
            from: [],
            events: events,
            now: start.addingTimeInterval(60 * 60)
        )

        XCTAssertTrue(blocks.contains { $0.kind == .observed && $0.label == "VS Code" && $0.end.timeIntervalSince($0.start) == 120 })
        XCTAssertTrue(blocks.contains { $0.kind == .unobserved && $0.label == "Unobserved / away" })
        let report = ReplayEngine().insightReport(blocks: blocks, driftEvents: [], focusScore: 90)
        XCTAssertTrue(report.productiveMinutes == 2)
        XCTAssertTrue(report.unobservedMinutes == 58)
        XCTAssertTrue(report.journalSummary.contains("unobserved"))
        XCTAssertTrue(report.nextAction.contains("fix collection"))
    }

    // insight report turns timeline blocks into journal metrics
    func testInsightReportBuildsJournalMetrics() {
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

        XCTAssertTrue(report.productiveMinutes == 70)
        XCTAssertTrue(report.studyLikeMinutes == 60)
        XCTAssertTrue(report.codingLikeMinutes == 10)
        XCTAssertTrue(report.deepWorkMinutes == 60)
        XCTAssertTrue(report.fragmentedProductiveMinutes == 10)
        XCTAssertTrue(report.distractingMinutes == 15)
        XCTAssertTrue(report.idleMinutes == 15)
        XCTAssertTrue(report.neutralMinutes == 0)
        XCTAssertTrue(report.driftCount == 1)
        XCTAssertTrue(report.longestProductiveBlockLabel == "Research reading")
        XCTAssertTrue(report.topActivities.first == ActivityBreakdownItem(label: "Research reading", category: .productive, minutes: 60))
        XCTAssertTrue(report.topActivities.contains(ActivityBreakdownItem(label: "Twitter", category: .distracting, minutes: 15)))
        XCTAssertTrue(report.topProductiveLabels.first == "Research reading")
        XCTAssertTrue(report.topDistractions.first == "Twitter")
        XCTAssertTrue(!report.nextAction.isEmpty)
        XCTAssertTrue(report.journalSummary.contains("productive"))
        XCTAssertTrue(report.journalSummary.contains("Distracting/wasted"))
    }

    // insight report warns about suspiciously long active blocks
    func testInsightReportWarnsAboutLongUnsplitBlocks() {
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

        XCTAssertTrue(report.dataQualityWarnings.contains { $0.contains("VS Code") })
    }

    // insight report suggests category calibration for high neutral time
    func testInsightReportSuggestsCategoryCalibration() {
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

        XCTAssertTrue(report.calibrationSuggestions.contains { $0.contains("edit categories") })
        XCTAssertTrue(report.calibrationSuggestions.contains { $0.contains("Unknown Research Tool") })
    }

    // AI support near notes counts as study workflow
    func testAiSupportNearNotesCountsAsStudyWorkflow() {
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

        XCTAssertTrue(report.productiveMinutes == 45)
        XCTAssertTrue(report.studyLikeMinutes == 45)
    }
}
