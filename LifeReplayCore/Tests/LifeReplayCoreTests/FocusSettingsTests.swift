import XCTest
@testable import LifeReplayCore

final class FocusSettingsTests: XCTestCase {
    // settings map to engine configuration
    func testSettingsMapToConfiguration() {
        let settings = FocusSettings(
            idleThresholdSeconds: 120,
            sessionMinimumDurationSeconds: 45,
            driftWindowMinutes: 8,
            baselineSwitchesPerHour: 10,
            productiveSessionMinimumMinutes: 4,
            maximumObservationGapSeconds: 75
        )

        let configuration = settings.focusEngineConfiguration

        XCTAssertTrue(configuration.idleThresholdSeconds == 120)
        XCTAssertTrue(configuration.sessionMinimumDuration == 45)
        XCTAssertTrue(configuration.driftWindow == 480)
        XCTAssertTrue(configuration.defaultBaselineSwitchesPerHour == 10)
        XCTAssertTrue(configuration.productiveSessionMinimumDuration == 240)
        XCTAssertTrue(configuration.maximumObservedGap == 75)
    }
}
