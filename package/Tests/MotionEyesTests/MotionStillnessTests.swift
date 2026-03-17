import XCTest
@testable import MotionEyes

final class MotionStillnessTests: XCTestCase {
    func testFlatTracePassesDefaultStillnessThreshold() {
        let result = MotionStillness.evaluate([42, 42, 42, 42])

        XCTAssertEqual(result.movementRange, 0, accuracy: 0.0001)
        XCTAssertEqual(result.largestStep, 0, accuracy: 0.0001)
        XCTAssertTrue(MotionStillness.isStill([42, 42, 42, 42]))
    }

    func testSubThresholdJitterCountsAsStill() {
        let values = [100.0, 100.06, 99.97, 100.11, 100.02]
        let result = MotionStillness.evaluate(values)

        XCTAssertEqual(result.movementRange, 0.14, accuracy: 0.0001)
        XCTAssertTrue(MotionStillness.isStill(values))
    }

    func testExcursionAndReturnFailsStillness() {
        let values = [320.0, 320.18, 320.0, 319.84, 320.0]
        let result = MotionStillness.evaluate(values)

        XCTAssertEqual(result.movementRange, 0.34, accuracy: 0.0001)
        XCTAssertFalse(MotionStillness.isStill(values))
    }

    func testCustomThresholdAllowsSlightlyLargerDrift() {
        let values = [0.0, 0.08, 0.17, 0.24]

        XCTAssertFalse(MotionStillness.isStill(values, maximumMovement: 0.2))
        XCTAssertTrue(MotionStillness.isStill(values, maximumMovement: 0.25))
    }

    func testTinyNoiseCanStillPassZeroThresholdViaEpsilon() {
        let values = [1.0, 1.00005, 1.0]
        let result = MotionStillness.evaluate(values, epsilon: 0.0001)

        XCTAssertEqual(result.movementRange, 0, accuracy: 0.0001)
        XCTAssertTrue(MotionStillness.isStill(values, maximumMovement: 0, epsilon: 0.0001))
    }

    func testMaximumMovementIsClampedToZero() {
        let values = [0.0, 0.1, 0.0]

        XCTAssertFalse(MotionStillness.isStill(values, maximumMovement: -1))
        XCTAssertTrue(MotionStillness.isStill([5.0, 5.0], maximumMovement: -1))
    }
}
