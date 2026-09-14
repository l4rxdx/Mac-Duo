import XCTest
@testable import MacDuo

final class WakeAnimationCoordinatorTests: XCTestCase {
    func testClamshellWakeStartsOnlyAfterWorkspaceAndScreenWake() {
        var coordinator = armedCoordinator()

        coordinator.workspaceDidWake()
        XCTAssertEqual(coordinator.observe(angle: 25, releaseHysteresis: 4), .none)

        coordinator.screensDidWake()
        XCTAssertEqual(
            coordinator.observe(angle: 25, releaseHysteresis: 4),
            .start(.init(startAngle: 90))
        )
        XCTAssertTrue(coordinator.isOpening)
    }

    func testWakeEventsMayArriveInEitherOrder() {
        var coordinator = armedCoordinator()

        coordinator.screensDidWake()
        coordinator.workspaceDidWake()

        XCTAssertEqual(
            coordinator.observe(angle: 40, releaseHysteresis: 4),
            .start(.init(startAngle: 90))
        )
    }

    func testDarkWakeDoesNotStartAnimation() {
        var coordinator = armedCoordinator()

        coordinator.workspaceDidWake()

        XCTAssertEqual(coordinator.observe(angle: 15, releaseHysteresis: 4), .none)
        XCTAssertFalse(coordinator.isOpening)
    }

    func testAlreadyOpenLidCancelsStaleAnimation() {
        var coordinator = armedCoordinator()
        coordinator.workspaceDidWake()
        coordinator.screensDidWake()

        XCTAssertEqual(coordinator.observe(angle: 96, releaseHysteresis: 4), .cancel)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testMenuSleepWithoutClosingEffectDoesNotArm() {
        var coordinator = WakeAnimationCoordinator()

        coordinator.armForSleep(
            effectWasActive: false,
            effectWasPreview: false,
            isEnabled: true,
            wasClosingRecently: true,
            startAngle: 90,
            currentAngle: 10
        )
        coordinator.workspaceDidWake()
        coordinator.screensDidWake()

        XCTAssertEqual(coordinator.observe(angle: 20, releaseHysteresis: 4), .none)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testManualSleepAtPartiallyClosedAngleDoesNotArm() {
        var coordinator = WakeAnimationCoordinator()

        coordinator.armForSleep(
            effectWasActive: true,
            effectWasPreview: false,
            isEnabled: true,
            wasClosingRecently: true,
            startAngle: 90,
            currentAngle: 40
        )
        coordinator.workspaceDidWake()
        coordinator.screensDidWake()

        XCTAssertEqual(coordinator.observe(angle: 40, releaseHysteresis: 4), .none)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testDisabledLockScreenOptionDoesNotArm() {
        var coordinator = WakeAnimationCoordinator()

        coordinator.armForSleep(
            effectWasActive: true,
            effectWasPreview: false,
            isEnabled: false,
            wasClosingRecently: true,
            startAngle: 90,
            currentAngle: 8
        )
        coordinator.workspaceDidWake()
        coordinator.screensDidWake()

        XCTAssertEqual(coordinator.observe(angle: 20, releaseHysteresis: 4), .none)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testOpeningCompletesOnlyAfterRawAndSmoothedAnglesReachStart() {
        var coordinator = armedCoordinator()
        coordinator.workspaceDidWake()
        coordinator.screensDidWake()
        _ = coordinator.observe(angle: 20, releaseHysteresis: 4)

        XCTAssertFalse(coordinator.shouldFinish(rawAngle: 96, visualAngle: 86, releaseHysteresis: 4))
        XCTAssertFalse(coordinator.shouldFinish(rawAngle: 92, visualAngle: 91, releaseHysteresis: 4))
        XCTAssertTrue(coordinator.shouldFinish(rawAngle: 96, visualAngle: 90, releaseHysteresis: 4))
    }

    private func armedCoordinator() -> WakeAnimationCoordinator {
        var coordinator = WakeAnimationCoordinator()
        coordinator.armForSleep(
            effectWasActive: true,
            effectWasPreview: false,
            isEnabled: true,
            wasClosingRecently: true,
            startAngle: 90,
            currentAngle: 8
        )
        return coordinator
    }
}
