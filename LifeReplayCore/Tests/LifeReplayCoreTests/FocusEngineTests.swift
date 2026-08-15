import Foundation
import Testing
@testable import LifeReplayCore

@Suite("Focus engine")
struct FocusEngineTests {
    @Test("detects drift after sustained productive work")
    func detectsDriftAfterProductiveSession() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [
            event(start, app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(60), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(120), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(180), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(240), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(300), app: "VS Code", bundle: "com.microsoft.VSCode"),
            event(start.addingTimeInterval(6 * 60), app: "Terminal", bundle: "com.apple.Terminal"),
            event(start.addingTimeInterval(6 * 60 + 30), domain: "twitter.com"),
            event(start.addingTimeInterval(6 * 60 + 60), app: "Safari", bundle: "com.apple.Safari"),
            event(start.addingTimeInterval(6 * 60 + 90), domain: "youtube.com"),
            event(start.addingTimeInterval(6 * 60 + 120), app: "Messages", bundle: "com.apple.MobileSMS"),
        ]

        let engine = FocusEngine(configuration: .init(defaultBaselineSwitchesPerHour: 6))
        let analysis = engine.analyze(events: events)

        #expect(analysis.driftEvents.count == 1)
        #expect(analysis.driftEvents[0].triggerAppNames.contains("Twitter / X"))
        #expect(analysis.driftEvents[0].switchCountInWindow >= 4)
        #expect(analysis.driftEvents[0].timestamp == start.addingTimeInterval(6 * 60 + 30))
    }

    @Test("does not detect drift without distracting apps")
    func ignoresHighSwitchingWithoutDistraction() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [
            event(start, app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(60), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(120), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(180), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(240), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(300), app: "VS Code", bundle: "com.microsoft.VSCode"),
            event(start.addingTimeInterval(6 * 60), app: "Terminal", bundle: "com.apple.Terminal"),
            event(start.addingTimeInterval(6 * 60 + 30), app: "Mail", bundle: "com.apple.mail"),
            event(start.addingTimeInterval(6 * 60 + 60), app: "Calendar", bundle: "com.apple.iCal"),
            event(start.addingTimeInterval(6 * 60 + 90), app: "Messages", bundle: "com.apple.MobileSMS"),
        ]

        let engine = FocusEngine(configuration: .init(defaultBaselineSwitchesPerHour: 6))
        let analysis = engine.analyze(events: events)

        #expect(analysis.driftEvents.isEmpty)
    }

    @Test("does not double count app activation and browser capture for one switch")
    func doesNotDoubleCountSameTimestampBrowserCapture() {
        let start = Date(timeIntervalSince1970: 0)
        let triggerTime = start.addingTimeInterval(6 * 60)
        let events = [
            event(start, app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(60), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(120), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(180), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(240), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(300), app: "VS Code", bundle: "com.microsoft.VSCode"),
            event(triggerTime, app: "Safari", bundle: "com.apple.Safari"),
            event(triggerTime, domain: "twitter.com"),
        ]

        let engine = FocusEngine(configuration: .init(defaultBaselineSwitchesPerHour: 6))
        let analysis = engine.analyze(events: events)

        #expect(analysis.driftEvents.isEmpty)
    }

    @Test("scores productive days higher than distracted days")
    func scoresProductiveDayHigher() {
        let start = Date(timeIntervalSince1970: 0)
        let productive = [
            FocusSession(start: start, end: start.addingTimeInterval(3600), category: .productive),
        ]
        let distracted = [
            FocusSession(start: start, end: start.addingTimeInterval(1200), category: .productive),
            FocusSession(start: start.addingTimeInterval(1200), end: start.addingTimeInterval(3600), category: .distracting),
        ]
        let engine = FocusEngine()

        #expect(engine.score(sessions: productive, driftEvents: []) > engine.score(sessions: distracted, driftEvents: []))
    }

    @Test("idle overlap is applied to sessions")
    func idleOverlapIsAppliedToSessions() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [
            event(start, app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(60), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(120), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(180), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(240), app: "VS Code", bundle: "com.microsoft.VSCode"),
            ActivityEvent(timestamp: start.addingTimeInterval(300), kind: .idleStart),
            ActivityEvent(timestamp: start.addingTimeInterval(600), kind: .idleEnd),
            heartbeat(start.addingTimeInterval(660), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(720), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(780), app: "VS Code", bundle: "com.microsoft.VSCode"),
            heartbeat(start.addingTimeInterval(840), app: "VS Code", bundle: "com.microsoft.VSCode"),
            event(start.addingTimeInterval(900), app: "Terminal", bundle: "com.apple.Terminal"),
        ]

        let analysis = FocusEngine().analyze(events: events)

        #expect(analysis.sessions.first?.idleSeconds == 0)
        #expect(analysis.sessions.first?.end == start.addingTimeInterval(300))
        #expect(analysis.sessions.first.map { $0.end!.timeIntervalSince($0.start) } == 300)
    }
}

private func event(_ timestamp: Date, app: String? = nil, bundle: String? = nil, domain: String? = nil) -> ActivityEvent {
    ActivityEvent(
        timestamp: timestamp,
        kind: domain == nil ? .appActivated : .browserDomain,
        appBundleID: bundle,
        appName: app,
        browserDomain: domain
    )
}

private func heartbeat(_ timestamp: Date, app: String, bundle: String) -> ActivityEvent {
    ActivityEvent(
        timestamp: timestamp,
        kind: .heartbeat,
        appBundleID: bundle,
        appName: app
    )
}
