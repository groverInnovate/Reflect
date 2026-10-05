import Foundation
import XCTest
@testable import LifeReplayCore

final class WorkdayReportTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 0)
    func event(_ offset: Double, _ kind: ActivityKind, _ name: String? = nil) -> ActivityEvent {
        ActivityEvent(timestamp: start.addingTimeInterval(offset), kind: kind, appName: name)
    }
    func testShortVisitsAccumulateWithoutRoundingLoss() {
        let blocks = (0..<20).map { index in
            TimelineBlock(start: start.addingTimeInterval(Double(index * 20)),
                end: start.addingTimeInterval(Double((index + 1) * 20)),
                label: index.isMultiple(of: 2) ? "Editor" : "Terminal", category: .productive)
        }
        let report = WorkdayReport(blocks: blocks)
        XCTAssertTrue(report.activeSeconds == 400)
        XCTAssertTrue(report.productiveSeconds == 400)
        XCTAssertTrue(report.activities.count == 2)
        XCTAssertTrue(report.activities.allSatisfy { $0.seconds == 200 })
    }
    func testPauseImmediatelyEndsAppAttribution() {
        let blocks = ActivityTimelineEngine().blocks(from: [event(0, .appActivated, "Editor"),
            event(20, .trackingStopped), event(100, .appActivated, "Terminal")],
            resolver: CategoryResolver(), now: start.addingTimeInterval(120))
        let report = WorkdayReport(blocks: blocks)
        XCTAssertTrue(report.activeSeconds == 40)
        XCTAssertTrue(report.unobservedSeconds == 80)
        XCTAssertTrue(report.idleSeconds == 0)
    }
    func testIdleEndDoesNotResurrectStaleSurface() {
        let report = WorkdayReport(blocks: ActivityTimelineEngine().blocks(from: [event(0, .appActivated, "Editor"),
            event(60, .idleStart), event(180, .idleEnd), event(240, .appActivated, "Terminal")],
            resolver: CategoryResolver(), now: start.addingTimeInterval(300)))
        XCTAssertTrue(report.activeSeconds == 120)
        XCTAssertTrue(report.idleSeconds == 120)
        XCTAssertTrue(report.unobservedSeconds == 60)
        XCTAssertTrue(report.activities.first { $0.label == "Editor" }?.seconds == 60)
    }
    func testFutureEventsCannotExtendAReport() {
        let blocks = ActivityTimelineEngine().blocks(from: [event(0, .appActivated, "Editor"),
            event(600, .appActivated, "Other")], resolver: CategoryResolver(), now: start.addingTimeInterval(30))
        XCTAssertTrue(blocks.count == 1)
        XCTAssertTrue(blocks[0].end == start.addingTimeInterval(30))
    }
    func testSameInstantDomainWinsRegardlessOfInputOrder() {
        let events = [ActivityEvent(timestamp: start, kind: .browserDomain, browserDomain: "github.com"),
                      event(0, .appActivated, "Browser")]
        let blocks = ActivityTimelineEngine().blocks(from: events, resolver: CategoryResolver(), now: start.addingTimeInterval(30))
        XCTAssertTrue(blocks.count == 1)
        XCTAssertTrue(blocks[0].label == "GitHub")
    }
    func testTimelineCompactionDoesNotFillMissingTime() {
        let blocks = [TimelineBlock(start: start, end: start.addingTimeInterval(20), label: "Editor", category: .productive),
            TimelineBlock(start: start.addingTimeInterval(40), end: start.addingTimeInterval(60), label: "Editor", category: .productive)]
        XCTAssertTrue(WorkdayReport(blocks: blocks).blocks.count == 2)
        XCTAssertTrue(ReplayEngine().timelineBlocks(from: blocks.map {
            FocusSession(start: $0.start, end: $0.end, category: .productive, primaryAppName: "Editor")
        }).count == 2)
    }
    func testHourlyBucketsSplitAtHourBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let report = WorkdayReport(blocks: [TimelineBlock(start: start.addingTimeInterval(3500),
            end: start.addingTimeInterval(3700), label: "Editor", category: .productive)], calendar: calendar)
        XCTAssertTrue(report.hours.count == 2)
        XCTAssertTrue(report.hours.allSatisfy { $0.productive == 100 })
        XCTAssertTrue(report.hours.reduce(0) { $0 + $1.active } == report.activeSeconds)
    }
    func testAllActivitiesRemainAvailableBeyondEight() {
        let report = WorkdayReport(blocks: (0..<12).map { index in
            TimelineBlock(start: start.addingTimeInterval(Double(index * 20)),
                end: start.addingTimeInterval(Double((index + 1) * 20)), label: "App \(index)", category: .neutral)
        })
        XCTAssertTrue(report.activities.count == 12)
    }
    func testDomainMatchingRespectsBoundariesAndEvidencePriority() {
        let resolver = CategoryResolver()
        let falseMatch = ActivityEvent(timestamp: start, kind: .browserDomain, browserDomain: "examplex.com")
        XCTAssertTrue(resolver.category(for: falseMatch) == .neutral)
        let youtube = ActivityEvent(timestamp: start, kind: .browserDomain, windowTitle: "Rust lecture - GitHub", browserDomain: "youtube.com")
        XCTAssertTrue(resolver.category(for: youtube) == .distracting)
        let subdomain = ActivityEvent(timestamp: start, kind: .browserDomain, browserDomain: "m.youtube.com")
        XCTAssertTrue(resolver.displayName(for: subdomain) == "YouTube")
    }
    func testMidnightCarryKeepsOriginalObservationExpiry() {
        let blocks = ActivityTimelineEngine(configuration: .init(maximumObservedGap: 30)).blocks(
            from: [event(-20, .heartbeat, "Editor")], resolver: CategoryResolver(), now: start.addingTimeInterval(40))
        let report = WorkdayReport(blocks: blocks, interval: DateInterval(start: start, end: start.addingTimeInterval(40)))
        XCTAssertTrue(report.activeSeconds == 10)
        XCTAssertTrue(report.unobservedSeconds == 30)
        XCTAssertTrue(report.blocks.allSatisfy { $0.start >= start })
    }
    func testOvernightIdleIsClippedToSelectedDay() {
        let blocks = ActivityTimelineEngine().blocks(from: [event(-3600, .idleStart), event(60, .idleEnd)],
            resolver: CategoryResolver(), now: start.addingTimeInterval(120))
        let report = WorkdayReport(blocks: blocks, interval: DateInterval(start: start, end: start.addingTimeInterval(120)))
        XCTAssertTrue(report.idleSeconds == 60)
        XCTAssertTrue(report.unobservedSeconds == 60)
        XCTAssertTrue(report.activeSeconds == 0)
    }
    func testEmptyHoursRemainVisibleBetweenWorkSessions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let report = WorkdayReport(blocks: [
            TimelineBlock(start: start, end: start.addingTimeInterval(30), label: "Editor", category: .productive),
            TimelineBlock(start: start.addingTimeInterval(7200), end: start.addingTimeInterval(7230), label: "Editor", category: .productive)
        ], calendar: calendar)
        XCTAssertTrue(report.hours.count == 3)
        XCTAssertTrue(report.hours[1].active == 0)
    }
    func testEmptyDayHasNoInventedActivity() {
        let report = WorkdayReport(blocks: [])
        XCTAssertTrue(report.activeSeconds == 0 && report.idleSeconds == 0 && report.unobservedSeconds == 0)
        XCTAssertTrue(report.blocks.isEmpty && report.hours.isEmpty && report.activities.isEmpty)
    }
    func testHourlyAccountingConservesSecondsAcrossDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let beginning = Date(timeIntervalSince1970: 1730611800)
        let report = WorkdayReport(blocks: [TimelineBlock(start: beginning, end: beginning.addingTimeInterval(7200),
            label: "Editor", category: .productive)], calendar: calendar)
        XCTAssertTrue(report.activeSeconds == 7200)
        XCTAssertTrue(report.hours.reduce(0) { $0 + $1.active } == 7200)
        XCTAssertTrue(Set(report.hours.map(\.id)).count == report.hours.count)
    }
}
