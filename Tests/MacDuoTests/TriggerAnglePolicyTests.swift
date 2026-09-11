import XCTest
@testable import MacDuo

final class TriggerAnglePolicyTests: XCTestCase {
    func testPositiveOffsetDelaysAdaptiveTrigger() {
        XCTAssertEqual(resolved(learned: 111, offset: 10), 101)
    }

    func testNegativeOffsetAdvancesAdaptiveTrigger() {
        XCTAssertEqual(resolved(learned: 111, offset: -10), 121)
    }

    func testZeroOffsetUsesLearnedAngle() {
        XCTAssertEqual(resolved(learned: 111, offset: 0), 111)
    }

    func testAdaptiveModeFallsBackToManualAngleBeforeLearning() {
        XCTAssertEqual(resolved(learned: nil, offset: 3), 87)
    }

    func testManualModeIgnoresLearnedAngleAndOffset() {
        XCTAssertEqual(
            TriggerAnglePolicy.resolvedStartAngle(
                manualAngle: 90,
                learnedAngle: 111,
                adaptiveEnabled: false,
                adaptiveOffset: 30
            ),
            90
        )
    }

    func testResolvedAngleStaysWithinSensorRange() {
        XCTAssertEqual(resolved(learned: 20, offset: 30), 5)
        XCTAssertEqual(resolved(learned: 120, offset: -30), 130)
    }

    func testOffsetIsLimitedToConfiguredRange() {
        XCTAssertEqual(resolved(learned: 100, offset: 100), 70)
        XCTAssertEqual(resolved(learned: 100, offset: -100), 130)
    }

    private func resolved(learned: Double?, offset: Double) -> Double {
        TriggerAnglePolicy.resolvedStartAngle(
            manualAngle: 90,
            learnedAngle: learned,
            adaptiveEnabled: true,
            adaptiveOffset: offset
        )
    }
}
