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
        let report = WorkdayReport(blocks: blocks)
        XCTAssertTrue(report.productiveSeconds == 120)
        XCTAssertTrue(report.unobservedSeconds == 58 * 60)
    }








}
