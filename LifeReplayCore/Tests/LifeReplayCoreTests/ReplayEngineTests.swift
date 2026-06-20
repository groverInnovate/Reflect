import Foundation
import Testing
@testable import LifeReplayCore

@Suite("Replay engine")
struct ReplayEngineTests {
    @Test("merges adjacent blocks of same category under gap threshold")
    func mergesAdjacentBlocks() {
        let start = Date(timeIntervalSince1970: 0)
        let sessions = [
            FocusSession(start: start, end: start.addingTimeInterval(600), category: .productive, primaryAppName: "VS Code"),
            FocusSession(start: start.addingTimeInterval(700), end: start.addingTimeInterval(1200), category: .productive, primaryAppName: "Terminal"),
            FocusSession(start: start.addingTimeInterval(1500), end: start.addingTimeInterval(1800), category: .neutral, primaryAppName: "Mail"),
        ]

        let blocks = ReplayEngine().timelineBlocks(from: sessions)

        #expect(blocks.count == 2)
        #expect(blocks[0].category == .productive)
        #expect(blocks[0].end == start.addingTimeInterval(1200))
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

        #expect(blocks.contains { $0.label == "Idle period" && $0.start == start.addingTimeInterval(900) })
    }
}
