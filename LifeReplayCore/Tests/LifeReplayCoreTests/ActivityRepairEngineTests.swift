import Foundation
import Testing
@testable import LifeReplayCore

@Suite("Activity repair engine")
struct ActivityRepairEngineTests {
    @Test("infers idle events across long unmarked gaps")
    func infersIdleAcrossLongGaps() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [
            ActivityEvent(timestamp: start, kind: .appActivated, appName: "VS Code"),
            ActivityEvent(timestamp: start.addingTimeInterval(2 * 3_600), kind: .appActivated, appName: "Terminal"),
        ]

        let repairs = ActivityRepairEngine().inferredIdleEvents(from: events)

        #expect(repairs.count == 2)
        #expect(repairs[0].kind == .idleStart)
        #expect(repairs[0].timestamp == start.addingTimeInterval(90))
        #expect(repairs[1].kind == .idleEnd)
        #expect(repairs[1].timestamp == start.addingTimeInterval(2 * 3_600))
        #expect(repairs.allSatisfy { $0.source == "mac-repair" })
    }

    @Test("does not duplicate gaps that already have idle markers")
    func skipsAlreadyMarkedIdleGaps() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [
            ActivityEvent(timestamp: start, kind: .appActivated, appName: "VS Code"),
            ActivityEvent(timestamp: start.addingTimeInterval(90), kind: .idleStart),
            ActivityEvent(timestamp: start.addingTimeInterval(2 * 3_600), kind: .idleEnd),
            ActivityEvent(timestamp: start.addingTimeInterval(2 * 3_600 + 10), kind: .appActivated, appName: "Terminal"),
        ]

        let repairs = ActivityRepairEngine().inferredIdleEvents(from: events)

        #expect(repairs.isEmpty)
    }
}
