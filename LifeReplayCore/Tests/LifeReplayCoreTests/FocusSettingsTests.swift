import Testing
@testable import LifeReplayCore

@Suite("Focus settings")
struct FocusSettingsTests {
    @Test("settings map to engine configuration")
    func settingsMapToConfiguration() {
        let settings = FocusSettings(
            idleThresholdSeconds: 120,
            sessionMinimumDurationSeconds: 45,
            driftWindowMinutes: 8,
            baselineSwitchesPerHour: 10,
            productiveSessionMinimumMinutes: 4
        )

        let configuration = settings.focusEngineConfiguration

        #expect(configuration.idleThresholdSeconds == 120)
        #expect(configuration.sessionMinimumDuration == 45)
        #expect(configuration.driftWindow == 480)
        #expect(configuration.defaultBaselineSwitchesPerHour == 10)
        #expect(configuration.productiveSessionMinimumDuration == 240)
    }
}
