import XCTest
@testable import RatTamerCore

final class ThumbWheelClassifierTests: XCTestCase {
    func testIsThumbWheelAcceptsDiscreteHorizontalScroll() {
        XCTAssertTrue(ThumbWheel.isThumbWheel(deltaX: 1, deltaY: 0, isContinuous: 0, phase: 0))
        XCTAssertTrue(ThumbWheel.isThumbWheel(deltaX: -10, deltaY: 0, isContinuous: 0, phase: 0))
    }

    func testIsThumbWheelRejectsTrackpadContinuous() {
        XCTAssertFalse(ThumbWheel.isThumbWheel(deltaX: 10, deltaY: 0, isContinuous: 1, phase: 0))
    }

    func testIsThumbWheelRejectsVerticalAndZero() {
        XCTAssertFalse(ThumbWheel.isThumbWheel(deltaX: 0, deltaY: 1, isContinuous: 0, phase: 0))
        XCTAssertFalse(ThumbWheel.isThumbWheel(deltaX: 0, deltaY: 0, isContinuous: 0, phase: 0))
    }

    func testIsThumbWheelRejectsScrollPhase() {
        XCTAssertFalse(ThumbWheel.isThumbWheel(deltaX: 10, deltaY: 0, isContinuous: 0, phase: 1))
    }

    func testDirectionFromDeltaX() {
        XCTAssertEqual(ThumbWheel.direction(forDeltaX: 10), .right)
        XCTAssertEqual(ThumbWheel.direction(forDeltaX: -10), .left)
    }

    func testAccumulatorFiresNotchAtThreshold() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 10, direction: .right), 1)
    }

    func testAccumulatorFiresPerThreshold() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 10, direction: .right), 1)
        XCTAssertEqual(acc.push(pixels: 10, direction: .right), 1)
    }

    func testAccumulatorKeepsRemainder() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 15, direction: .right), 1)
        XCTAssertEqual(acc.push(pixels: 5, direction: .right), 1)
    }

    func testAccumulatorHandlesLargeSingleDelta() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 25, direction: .right), 2)
    }

    func testAccumulatorLeftDirection() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 10, direction: .left), 1)
    }

    func testAccumulatorSignFlushDiscardsOppositeRemainder() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 5, direction: .right), 0)
        XCTAssertEqual(acc.push(pixels: 10, direction: .left), 1)
    }

    func testAccumulatorIgnoresZeroPixels() {
        var acc = ThumbWheel.NotchAccumulator()
        XCTAssertEqual(acc.push(pixels: 0, direction: .right), 0)
        XCTAssertEqual(acc.push(pixels: 0, direction: .right), 0)
    }

    func testResetClearsPending() {
        var acc = ThumbWheel.NotchAccumulator()
        _ = acc.push(pixels: 5, direction: .right)
        acc.reset()
        XCTAssertEqual(acc.push(pixels: 5, direction: .right), 0)
    }
}
