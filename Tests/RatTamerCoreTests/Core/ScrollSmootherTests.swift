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

    func testDetentBounceReverseDeltaIsDamped() {
        let s = make()
        _ = feed(s, at: 1000) // +10 establishes up direction
        // -3 -> -2.0px raw, within 40ms and < 50% of 10 -> bounce damped to
        // -0.3, then arrival boost x2.6 -> -0.78 (not the full -2.0/-5.2)
        let bounce = feed(s, deltaV: -3, at: 1000.01)
        XCTAssertEqual(bounce, -0.78, accuracy: 0.01)
    }

    func testRealReversalPassesThrough() {
        let s = make()
        _ = feed(s, at: 1000) // +10
        // -15 -> -10px raw, >= 50% of 10 -> not damped; boost x2.6 -> -26
        let reversal = feed(s, deltaV: -15, at: 1000.01)
        XCTAssertEqual(reversal, -26, accuracy: 0.01)
    }

    func testBounceAfterWindowPassesNormally() {
        let s = make()
        _ = feed(s, at: 1000) // +10
        // -3 after the 40ms bounce window -> normal (no boost, dt 0.1)
        let late = feed(s, deltaV: -3, at: 1000.1)
        XCTAssertEqual(late, -2.0, accuracy: 0.0001)
    }

    func testBounceDoesNotFlipDirection() {
        let s = make()
        _ = feed(s, at: 1000) // +10
        _ = feed(s, deltaV: -3, at: 1000.01) // bounce, damped
        // next dominant-direction feed is unaffected
        let next = feed(s, at: 1000.1)
        XCTAssertEqual(next, 10, accuracy: 0.0001)
    }

    func testReversalRequiresTwoConsecutiveOppositePulses() {
        let s = make()
        _ = feed(s, at: 1000) // +10
        // single opposite pulse: passes but does not flip the established direction
        _ = feed(s, deltaV: -15, at: 1000.01)
        // second opposite pulse confirms the reversal
        let second = feed(s, deltaV: -15, at: 1000.02)
        XCTAssertEqual(second, -26, accuracy: 0.01)
        // after the flip, a small opposite (up) pulse is damped as bounce
        let smallUp = feed(s, deltaV: 2, at: 1000.03)
        XCTAssertEqual(smallUp, 0.52, accuracy: 0.01)
    }

    func testCustomPixelsPerNotchIsHonored() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15, momentumEnabled: false, invert: false,
                                                 pixelsPerNotch: 20))
        XCTAssertEqual(feed(s, at: 1000), 20, accuracy: 0.0001)
    }

    func testCustomMaxBoostIsHonored() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15, momentumEnabled: false, invert: false,
                                                 maxBoost: 2.0))
        _ = feed(s, at: 1000)
        // 10ms gap -> boost = 1 + (2-1)*(1 - 0.01/0.05) = 1.8 -> 18
        XCTAssertEqual(feed(s, at: 1000.01), 18, accuracy: 0.0001)
    }

    func testCustomMomentumDecayIsHonored() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15, momentumEnabled: true, invert: false,
                                                 momentumDecay: 0.5))
        _ = feed(s, at: 1000)
        let t1 = Date(timeIntervalSince1970: 1000.2)
        let t2 = Date(timeIntervalSince1970: 1000.2 + 1.0 / 120.0)
        XCTAssertEqual(s.tick(at: t1), 10, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t2), 5, accuracy: 0.0001) // 10 * 0.5
    }

    func testGlideParameterDefaults() {
        let p = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: false, invert: false)
        XCTAssertEqual(p.smoothingEnabled, false)
        XCTAssertEqual(p.smoothFraction, ScrollSmoother.defaultSmoothFraction)
        XCTAssertEqual(p.glideStopThreshold, ScrollSmoother.defaultGlideStopThreshold)
    }

    private func makeGlide(multiplier: UInt8 = 15,
                           fraction: Double = 0.13,
                           stop: Double = 0.5,
                           pixelsPerNotch: Double = 10) -> ScrollSmoother {
        ScrollSmoother(parameters: .init(multiplier: multiplier,
                                         momentumEnabled: false,
                                         invert: false,
                                         pixelsPerNotch: pixelsPerNotch,
                                         smoothingEnabled: true,
                                         smoothFraction: fraction,
                                         glideStopThreshold: stop))
    }

    func testGlideFeedReturnsZeroAndAccumulates() {
        let s = makeGlide()
        XCTAssertEqual(feed(s, at: 1000), 0)
        XCTAssertGreaterThan(s.tick(at: Date(timeIntervalSince1970: 1000.02)), 0)
    }

    func testGlideSameDirectionAccumulates() {
        let s = makeGlide(fraction: 0.5, stop: 0.01)
        _ = feed(s, at: 1000)
        _ = feed(s, at: 1000.01)  // fast arrival → boost
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.02)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertGreaterThan(total, 20)  // 10 + boosted > 10
    }

    func testGlideBounceDoesNotAccumulate() {
        let s = makeGlide(fraction: 0.5, stop: 0.01)
        _ = feed(s, at: 1000)            // +10 target
        _ = feed(s, deltaV: -3, at: 1000.01)  // bounce → not accumulated
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.02)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertEqual(total, 10, accuracy: 1.0)
    }

    func testGlideReversalResetsAndAccumulates() {
        let s = makeGlide(fraction: 0.5, stop: 0.01)
        _ = feed(s, deltaV: 15, at: 1000)      // +10
        _ = feed(s, deltaV: 15, at: 1000.01)   // +boosted
        _ = s.tick(at: Date(timeIntervalSince1970: 1000.02))  // emit some +
        _ = feed(s, deltaV: -15, at: 1000.03)  // opposite, needs confirmation
        _ = feed(s, deltaV: -15, at: 1000.04)  // accepted reversal → reset + target neg
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.05)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertLessThan(total, -10)
    }
}
