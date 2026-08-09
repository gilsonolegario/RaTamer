import XCTest
@testable import RatTamerCore

final class SmoothnessLevelTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(SmoothnessLevel.min, 0)
        XCTAssertEqual(SmoothnessLevel.max, 100)
        XCTAssertEqual(SmoothnessLevel.defaultValue, 50)
        XCTAssertEqual(SmoothnessLevel.momentumOnThreshold, 20)
    }

    func testClampsOutOfRange() {
        XCTAssertEqual(SmoothnessLevel.clamped(-10), 0)
        XCTAssertEqual(SmoothnessLevel.clamped(150), 100)
        XCTAssertEqual(SmoothnessLevel.clamped(50), 50)
    }

    func testAnchorMaxBoost() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(0), 1.5, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(50), 3.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(100), 5.0, accuracy: 0.0001)
    }

    func testAnchorMomentumDecay() {
        XCTAssertEqual(SmoothnessLevel.momentumDecay(20), 0.75, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(50), 0.85, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(100), 0.92, accuracy: 0.0001)
    }

    func testMomentumThreshold() {
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(0))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(19))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(20))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(100))
    }

    func testInterpolationIsMonotonic() {
        let levels = stride(from: 0.0, through: 100.0, by: 10.0)
        let boosts = levels.map(SmoothnessLevel.maxBoost)
        let decays = levels.map(SmoothnessLevel.momentumDecay)
        for i in 1..<boosts.count {
            XCTAssertGreaterThan(boosts[i], boosts[i - 1])
            XCTAssertGreaterThan(decays[i], decays[i - 1])
        }
    }

    func testMidpointInterpolation() {
        // between 0 (1.5) and 50 (3.0): t = 0.5 -> 2.25
        XCTAssertEqual(SmoothnessLevel.maxBoost(25), 2.25, accuracy: 0.0001)
        // between 50 (0.85) and 100 (0.92): t = 0.5 -> 0.885
        XCTAssertEqual(SmoothnessLevel.momentumDecay(75), 0.885, accuracy: 0.0001)
    }

    func testParametersForDefaultLevel() {
        let p = SmoothnessLevel.parameters(level: 50, multiplier: 8, invert: true)
        XCTAssertEqual(p.multiplier, 8)
        XCTAssertEqual(p.invert, true)
        XCTAssertEqual(p.momentumEnabled, true)
        XCTAssertEqual(p.maxBoost, 3.0, accuracy: 0.0001)
        XCTAssertEqual(p.momentumDecay, 0.85, accuracy: 0.0001)
    }

    func testParametersDiscretaHasNoMomentum() {
        let p = SmoothnessLevel.parameters(level: 0, multiplier: 8, invert: false)
        XCTAssertFalse(p.momentumEnabled)
        XCTAssertEqual(p.maxBoost, 1.5, accuracy: 0.0001)
    }

    func testParametersKeepsTuningDefaults() {
        let p = SmoothnessLevel.parameters(level: 50, multiplier: 15, invert: false)
        XCTAssertEqual(p.pixelsPerNotch, 10, accuracy: 0.0001)
        XCTAssertEqual(p.bounceDamping, 0.15, accuracy: 0.0001)
        XCTAssertEqual(p.reversalConfirmation, 2)
    }
}
