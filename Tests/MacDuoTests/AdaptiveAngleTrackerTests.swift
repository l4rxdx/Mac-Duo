import XCTest
@testable import MacDuo

final class AdaptiveAngleTrackerTests: XCTestCase {
    func testLearnsMedianAfterConfiguredStableDuration() throws {
        var tracker = AdaptiveAngleTracker()
        var learned: Double?
        let jitter = [-0.2, 0, 0.2]

        for index in 0...96 {
            learned = tracker.observe(
                angle: 103 + jitter[index % jitter.count],
                at: Double(index) * 0.125,
                learningDuration: 12,
                isLearningAllowed: true
            ) ?? learned
        }

        XCTAssertEqual(try XCTUnwrap(learned), 103, accuracy: 0.01)
    }

    func testMovementRestartsLearningWindow() throws {
        var tracker = AdaptiveAngleTracker()

        for second in 0...5 {
            XCTAssertNil(tracker.observe(
                angle: 100,
                at: Double(second),
                learningDuration: 10,
                isLearningAllowed: true
            ))
        }
        XCTAssertNil(tracker.observe(
            angle: 95,
            at: 6,
            learningDuration: 10,
            isLearningAllowed: true
        ))

        var learned: Double?
        for second in 7...16 {
            learned = tracker.observe(
                angle: 95,
                at: Double(second),
                learningDuration: 10,
                isLearningAllowed: true
            ) ?? learned
        }

        XCTAssertEqual(try XCTUnwrap(learned), 95, accuracy: 0.01)
    }

    func testDisabledLearningClearsCandidate() {
        var tracker = AdaptiveAngleTracker()

        for second in 0...4 {
            _ = tracker.observe(
                angle: 108,
                at: Double(second),
                learningDuration: 5,
                isLearningAllowed: true
            )
        }
        XCTAssertNil(tracker.observe(
            angle: 108,
            at: 5,
            learningDuration: 5,
            isLearningAllowed: false
        ))
        XCTAssertNil(tracker.observe(
            angle: 108,
            at: 6,
            learningDuration: 5,
            isLearningAllowed: true
        ))
    }

    func testChangingDurationRestartsLearningWindow() {
        var tracker = AdaptiveAngleTracker()

        for second in 0...4 {
            _ = tracker.observe(
                angle: 110,
                at: Double(second),
                learningDuration: 5,
                isLearningAllowed: true
            )
        }
        XCTAssertNil(tracker.observe(
            angle: 110,
            at: 5,
            learningDuration: 12,
            isLearningAllowed: true
        ))
    }
}
