import Foundation
import Testing
@testable import LifeReplayCore

@Suite("Focus protection engine")
struct FocusProtectionEngineTests {
    @Test("signals when a distracting target follows a protected productive block")
    func signalsAfterProductiveBlock() {
        let start = Date(timeIntervalSince1970: 0)
        let trigger = ActivityEvent(
            timestamp: start.addingTimeInterval(12 * 60),
            kind: .browserDomain,
            appBundleID: "com.brave.Browser",
            browserDomain: "twitter.com"
        )
        let events = [
            ActivityEvent(
                timestamp: start,
                kind: .appActivated,
                appBundleID: "com.microsoft.VSCode",
                appName: "VS Code"
            ),
            ActivityEvent(
                timestamp: start.addingTimeInterval(8 * 60),
                kind: .appActivated,
                appBundleID: "com.apple.Terminal",
                appName: "Terminal"
            ),
            trigger,
        ]

        let signal = FocusProtectionEngine().signal(for: trigger, events: events)

        #expect(signal?.triggerName == "twitter.com")
        #expect(signal?.previousContext == "VS Code")
        #expect(signal?.productiveMinutes == 12)
    }

    @Test("does not signal for short productive blocks")
    func ignoresShortProductiveBlocks() {
        let start = Date(timeIntervalSince1970: 0)
        let trigger = ActivityEvent(
            timestamp: start.addingTimeInterval(2 * 60),
            kind: .browserDomain,
            browserDomain: "youtube.com"
        )
        let events = [
            ActivityEvent(
                timestamp: start,
                kind: .appActivated,
                appBundleID: "com.microsoft.VSCode",
                appName: "VS Code"
            ),
            trigger,
        ]

        let signal = FocusProtectionEngine().signal(for: trigger, events: events)

        #expect(signal == nil)
    }
}
