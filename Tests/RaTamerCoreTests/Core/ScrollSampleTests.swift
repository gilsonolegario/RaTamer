import XCTest
@testable import RaTamerCore

final class ScrollSampleTests: XCTestCase {
    func testRawPixelsMatchesFeedNativeOutput() {
        let smoother = ScrollSmoother(parameters: .init(multiplier: 8,
                                                        momentumEnabled: false,
                                                        invert: false,
                                                        pixelsPerNotch: 10))
        let movement = WheelMovement(deltaV: 80, periods: 1, resolution: true)
        XCTAssertEqual(smoother.rawPixels(for: movement), 100, accuracy: 0.0001)
        XCTAssertEqual(smoother.feed(movement, at: Date()), 100, accuracy: 0.0001)
    }

    func testRawPixelsComputesNotchesFromDeltaV() {
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: false,
                                                        invert: false,
                                                        pixelsPerNotch: 20))
        let movement = WheelMovement(deltaV: 45, periods: 1, resolution: true)
        XCTAssertEqual(smoother.rawPixels(for: movement), 60, accuracy: 0.0001)
    }

    func testScrollSampleEquality() {
        let a = ScrollSample(time: Date(timeIntervalSince1970: 1000), kind: .raw, value: 5)
        let b = ScrollSample(time: Date(timeIntervalSince1970: 1000), kind: .raw, value: 5)
        XCTAssertEqual(a, b)
    }
}