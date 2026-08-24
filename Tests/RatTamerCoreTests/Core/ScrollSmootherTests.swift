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
        let s = make(momentum: true)
        _ = feed(s, at: 1000)
        // 10ms gap -> boost = 1 + 2*(1 - 0.01/0.05) = 2.6
        let fast = feed(s, at: 1000.01)
        XCTAssertGreaterThan(fast, 10)
    }

    func testFeedSlowArrivalIsPrecise() {
        let s = make(momentum: true)
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
        let s = make(momentum: true, invert: true)
        XCTAssertEqual(feed(s, at: 1000), -10, accuracy: 0.0001)
    }

    func testInvertAppliesToMomentum() {
        let s = make(momentum: true, invert: true)
        _ = feed(s, at: 1000)
        XCTAssertLessThan(s.tick(at: Date(timeIntervalSince1970: 1000.2)), 0)
    }

    func testDetentBounceReverseDeltaIsDamped() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000) // +10 establishes up direction
        // -3 -> -2.0px raw, within 40ms and < 50% of 10 -> bounce damped to
        // -0.3, then arrival boost x2.6 -> -0.78 (not the full -2.0/-5.2)
        let bounce = feed(s, deltaV: -3, at: 1000.01)
        XCTAssertEqual(bounce, -0.78, accuracy: 0.01)
    }

    /// MX Master 2S ratchet rebound: an opposite pulse of ~75-85% of the last
    /// accepted magnitude arriving within ~50ms is a mechanical bounce, not a
    /// reversal. It must be damped, not emitted as backwards scroll.
    func testHighRatioBounceIsDamped() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000) // +10 establishes up direction
        // -13 -> -8.667px raw = 87% of 10, inside the 150ms window and
        // < 90% ratio -> damped to -8.667 * 0.15 = -1.3 (not the full -8.667)
        let bounce = feed(s, deltaV: -13, at: 1000.05)
        XCTAssertEqual(bounce, -1.3, accuracy: 0.01)
    }

    /// A genuine reversal is only accepted after `reversalConfirmation`
    /// consecutive opposite pulses — even a large single pulse never flips
    /// the dominant direction on its own.
    func testSingleOppositePulseNeverFlipsDirection() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000) // +10
        // -15 = 150% of 10 -> not a mechanical rebound, but still needs
        // confirmation; single pulse is damped and must not flip direction
        _ = feed(s, deltaV: -15, at: 1000.01)
        let next = feed(s, at: 1000.1) // dominant direction still wins
        XCTAssertEqual(next, 10, accuracy: 0.0001)
    }

    func testBounceDoesNotFlipDirection() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000) // +10
        _ = feed(s, deltaV: -3, at: 1000.01) // bounce, damped
        // next dominant-direction feed is unaffected
        let next = feed(s, at: 1000.1)
        XCTAssertEqual(next, 10, accuracy: 0.0001)
    }

    func testReversalRequiresThreeConsecutiveOppositePulses() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000) // +10
        // one or two opposite pulses never flip the established direction
        _ = feed(s, deltaV: -15, at: 1000.01)
        _ = feed(s, deltaV: -15, at: 1000.02)
        // third consecutive opposite pulse confirms the reversal
        let third = feed(s, deltaV: -15, at: 1000.03)
        XCTAssertEqual(third, -26, accuracy: 0.01)
        // after the flip, a small opposite (up) pulse is damped as bounce
        let smallUp = feed(s, deltaV: 2, at: 1000.04)
        XCTAssertEqual(smallUp, 0.52, accuracy: 0.01)
    }

    /// MX Master 2S ratchet regression: when a tooth settles between grooves,
    /// the wheel emits an isolated opposite pulse of the SAME magnitude as the
    /// main pulse, arriving long after the last feed (outside the bounce
    /// window). Such a pulse must never flip the dominant direction — only
    /// consecutive opposite pulses confirm a real reversal.
    func testRatchetLateIsolatedOppositePulseDoesNotReverse() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000) // +10 establishes up direction
        // -15 arrives 800ms later (outside the 150ms bounce window) with
        // magnitude equal to the main pulse -> damped, no direction flip
        let late = feed(s, deltaV: -15, at: 1000.8)
        XCTAssertEqual(late, -1.5, accuracy: 0.01) // -10 * damping, no boost
        // dominant direction continues to win
        let next = feed(s, at: 1001.0)
        XCTAssertEqual(next, 10, accuracy: 0.0001)
    }

    /// MX Master 2S ratchet regression (glide mode): an isolated opposite
    /// pulse arriving long after the feeds must not reset the glide target or
    /// emit backward scroll.
    func testRatchetLateIsolatedOppositePulseKeepsGlide() {
        let s = makeGlide(fraction: 0.5, stop: 0.01)
        _ = feed(s, at: 1000) // +10 target
        // -15 -> -10px, 800ms later, outside window, equal magnitude
        XCTAssertEqual(feed(s, deltaV: -15, at: 1000.8), 0)
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.82)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertGreaterThan(total, 0) // glide still drains the original target
    }

    func testCustomPixelsPerNotchIsHonored() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15, momentumEnabled: false, invert: false,
                                                 pixelsPerNotch: 20))
        XCTAssertEqual(feed(s, at: 1000), 20, accuracy: 0.0001)
    }

    func testCustomMaxBoostIsHonored() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15, momentumEnabled: true, invert: false,
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

    func testNativeBypassHasNoBoost() {
        let s = make()
        _ = feed(s, at: 1000)
        let fast = feed(s, at: 1000.01)
        XCTAssertEqual(fast, 10, accuracy: 0.0001)
    }

    func testNativeBypassSkipsBounceDamping() {
        let s = make()
        _ = feed(s, at: 1000)
        let reverse = feed(s, deltaV: -3, at: 1000.01)
        XCTAssertEqual(reverse, -2.0, accuracy: 0.0001)
    }

    /// Regression: Native preset (momentum + smoothing off) must still honor
    /// the configured scroll inversion — previously the pass-through branch
    /// returned the raw pixels and silently ignored `invert`.
    func testNativePassThroughAppliesInvertWhenMomentumAndSmoothingOff() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15,
                                                 momentumEnabled: false,
                                                 invert: true,
                                                 smoothingEnabled: false))
        XCTAssertEqual(feed(s, at: 1000), -10, accuracy: 0.0001)
    }

    func testNativeBypassDoesNotSeedMomentum() {
        let s = make()
        _ = feed(s, at: 1000)
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.2)), 0)
    }

    func testHasPendingWorkPassthroughNeverPending() {
        let s = make()
        _ = feed(s, at: 1000)
        XCTAssertFalse(s.hasPendingWork(at: Date(timeIntervalSince1970: 1000.01)))
    }

    func testHasPendingWorkMomentumDrainsToIdle() {
        let s = make(momentum: true)
        _ = feed(s, at: 1000)
        XCTAssertTrue(s.hasPendingWork(at: Date(timeIntervalSince1970: 1000.02)))
        XCTAssertTrue(s.hasPendingWork(at: Date(timeIntervalSince1970: 1000.2)))
        var t = Date(timeIntervalSince1970: 1000.2)
        while s.hasPendingWork(at: t) {
            _ = s.tick(at: t)
            t = t.addingTimeInterval(1.0 / 120.0)
        }
        XCTAssertFalse(s.hasPendingWork(at: t))
    }

    func testHasPendingWorkGlideDrainsToIdle() {
        let s = makeGlide()
        _ = feed(s, at: 1000)
        XCTAssertTrue(s.hasPendingWork(at: Date(timeIntervalSince1970: 1000.01)))
        var t = Date(timeIntervalSince1970: 1000.02)
        while s.hasPendingWork(at: t) {
            _ = s.tick(at: t)
            t = t.addingTimeInterval(1.0 / 120.0)
        }
        XCTAssertFalse(s.hasPendingWork(at: t))
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
        _ = feed(s, deltaV: -15, at: 1000.04)  // still confirming
        _ = feed(s, deltaV: -15, at: 1000.05)  // accepted reversal → reset + target neg
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.06)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertLessThan(total, -10)
    }

    func testGlideTickEmitsFractionOfRemaining() {
        let s = makeGlide(fraction: 0.5, stop: 0.01, pixelsPerNotch: 16)
        _ = feed(s, at: 1000)
        let t0 = Date(timeIntervalSince1970: 1000.02)
        XCTAssertEqual(s.tick(at: t0), 8, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(1.0 / 120)), 4, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(2.0 / 120)), 2, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(3.0 / 120)), 1, accuracy: 0.0001)
    }

    func testGlideConvergesAndStops() {
        let s = makeGlide(fraction: 0.5, stop: 0.01, pixelsPerNotch: 16)
        _ = feed(s, at: 1000)
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.02)
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
        }
        XCTAssertEqual(total, 16, accuracy: 0.001)
        XCTAssertEqual(s.tick(at: t.addingTimeInterval(1.0 / 120)), 0)
    }

    func testGlideStopThresholdEmitsRemainder() {
        let s = makeGlide(fraction: 0.5, stop: 2.0, pixelsPerNotch: 16)
        _ = feed(s, at: 1000)
        let t0 = Date(timeIntervalSince1970: 1000.02)
        XCTAssertEqual(s.tick(at: t0), 8, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(1.0 / 120)), 4, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(2.0 / 120)), 2, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(3.0 / 120)), 2, accuracy: 0.0001)
        XCTAssertEqual(s.tick(at: t0.addingTimeInterval(4.0 / 120)), 0)
    }

    func testGlideMinOnePixel() {
        let s = makeGlide(fraction: 0.13, stop: 0.01, pixelsPerNotch: 1)
        _ = feed(s, at: 1000)
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.02)), 1)
    }

    func testGlideConvergesWithZeroSmoothFraction() {
        // smoothFraction == 0 must still drain the target (one pixel per tick),
        // never spin forever emitting nothing.
        let s = makeGlide(fraction: 0.0, stop: 0.01, pixelsPerNotch: 16)
        _ = feed(s, at: 1000)
        var total = 0.0
        var t = Date(timeIntervalSince1970: 1000.02)
        var ticks = 0
        while true {
            let px = s.tick(at: t)
            if px == 0 { break }
            total += px
            t = t.addingTimeInterval(1.0 / 120)
            ticks += 1
            XCTAssertLessThan(ticks, 1000, "glide must converge")
        }
        XCTAssertEqual(total, 16, accuracy: 0.001)
    }

    func testGlideParamsIgnoredWhenSmoothingDisabled() {
        let s = ScrollSmoother(parameters: .init(multiplier: 15,
                                                 momentumEnabled: false,
                                                 invert: false,
                                                 smoothFraction: 0.99,
                                                 glideStopThreshold: 0.99))
        _ = feed(s, at: 1000)
        XCTAssertEqual(s.tick(at: Date(timeIntervalSince1970: 1000.02)), 0)
    }

    func testParametersCodableRoundTrip() throws {
        let p = ScrollSmoother.Parameters(
            multiplier: 8, momentumEnabled: true, invert: true,
            maxBoost: 4.2, momentumDecay: 0.91, pixelsPerNotch: 132,
            accelerationWindow: 0.05, feedGapTimeout: 0.09,
            momentumStopThreshold: 0.3, bounceWindow: 0.1,
            bounceRatio: 0.8, bounceDamping: 0.6,
            reversalConfirmation: 3, directionThreshold: 1.5,
            smoothingEnabled: true, smoothFraction: 0.13,
            glideStopThreshold: 0.5)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(ScrollSmoother.Parameters.self, from: data)
        XCTAssertEqual(back, p)
    }
}
