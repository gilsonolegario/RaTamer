import XCTest
@testable import RatTamerCore

final class ScrollSmootherTests: XCTestCase {
    private func make(multiplier: UInt8 = 15,
                      momentum: Bool = false,
                      invert: Bool = false) -> ScrollSmoother {
        ScrollSmoother(parameters: .init(multiplier: multiplier,
                                         momentumEnabled: momentum,
                                         invert: invert))
    }

    private func feed(_ smoother: ScrollSmoother, deltaV: Int16 = 15, at time: TimeInterval) -> Double {
        smoother.feed(WheelMovement(deltaV: deltaV, periods: 1, resolution: true),
                      at: Date(timeIntervalSince1970: time))
    }

    func testFeedConvertsDeltaToPixels() {
        // multiplier 15, deltaV 15 -> 1 notch * 10 px
        let s = make()
        XCTAssertEqual(feed(s, at: 1000), 10, accuracy: 0.0001)
    }

    func testFeedScalesByMultiplier() {
        // multiplier 8, deltaV 8 -> 1 notch * 10 px
        let s = make(multiplier: 8)
        XCTAssertEqual(feed(s, deltaV: 8, at: 1000), 10, accuracy: 0.0001)
    }

    func testFeedFastArrivalAccelerates() {
        let s = make()
        _ = feed(s, at: 1000)
        // 10ms gap -> boost = 1 + 2*(1 - 0.01/0.05) = 2.6
        let fast = feed(s, at: 1000.01)
        XCTAssertGreaterThan(fast, 10)
    }

    func testFeedSlowArrivalIsPrecise() {
        let s = make()
        _ = feed(s, at: 1000)
        // 500ms gap -> no boost
        let slow = feed(s, at: 1000.5)
        XCTAssertEqual(slow, 10, accuracy: 0.0001)
    }

    func testMomentumDecaysToZero() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000)
        var now = 1000.2 // past feedGapTimeout
        var ticks = 0
        while true {
            let px = s.tick(at: Date(timeIntervalSince1970: now))
            if px == 0 { break }
            ticks += 1
            now += 1.0 / 120.0
        }
        XCTAssertGreaterThan(ticks, 0)
    }

    func testMomentumDisabledReturnsZero() {
        let s = make(momentum: false)
        _ = feed(s, at: 1000)
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.2)), 0)
    }

    func testMomentumOnlyAfterFeedGap() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000)
        // still inside feedGapTimeout -> no momentum
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.02)), 0)
        // after gap -> momentum fires
        XCTAssertGreaterThan(s.tick(at: Date(timeIntervalSince1970: 1000.2)), 0)
    }

    func testInvertFlipsSign() {
        let s = make(invert: true)
        XCTAssertEqual(feed(s, at: 1000), -10, accuracy: 0.0001)
    }

    func testInvertAppliesToMomentum() {
        let s = make(momentum: true, invert: true)
        _ = feed(s, at: 1000)
        XCTAssertLessThan(s.tick(at: Date(timeIntervalSince1970: 1000.2)), 0)
    }
}
