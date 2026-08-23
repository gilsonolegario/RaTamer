import XCTest
@testable import RatTamerCore

final class ScrollWheelTapTests: XCTestCase {
    func testPassesThroughNonThumbWheelEvents() {
        let tap = ScrollWheelTap(shouldIntercept: { _ in true },
                                 onNotch: { _ in XCTFail("unexpected notch") })
        XCTAssertFalse(tap.process(deltaX: 0, deltaY: 1, isContinuous: 0, phase: 0, pointDeltaX: 0))
        XCTAssertFalse(tap.process(deltaX: 10, deltaY: 0, isContinuous: 1, phase: 0, pointDeltaX: 10))
    }

    func testPassesThroughWhenDirectionNotConfigured() {
        let tap = ScrollWheelTap(shouldIntercept: { _ in false },
                                 onNotch: { _ in XCTFail("unexpected notch") })
        XCTAssertFalse(tap.process(deltaX: 10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: 10))
    }

    func testSuppressesAndFiresNotchAfterPixelAccumulation() {
        var notches: [ThumbWheel.Direction] = []
        let tap = ScrollWheelTap(shouldIntercept: { _ in true }, onNotch: { notches.append($0) })
        XCTAssertTrue(tap.process(deltaX: 1, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: 1))
        XCTAssertEqual(notches, [])
        XCTAssertTrue(tap.process(deltaX: 10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: 10))
        XCTAssertEqual(notches, [.right])
    }

    func testSuppressesLeftDirection() {
        var notches: [ThumbWheel.Direction] = []
        let tap = ScrollWheelTap(shouldIntercept: { _ in true }, onNotch: { notches.append($0) })
        XCTAssertTrue(tap.process(deltaX: -10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: -10))
        XCTAssertEqual(notches, [.left])
    }

    func testOnlyConfiguredDirectionIsIntercepted() {
        var notches: [ThumbWheel.Direction] = []
        let tap = ScrollWheelTap(shouldIntercept: { $0 == .right }, onNotch: { notches.append($0) })
        XCTAssertFalse(tap.process(deltaX: -10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: -10))
        XCTAssertTrue(tap.process(deltaX: 10, deltaY: 0, isContinuous: 0, phase: 0, pointDeltaX: 10))
        XCTAssertEqual(notches, [.right])
    }
}
