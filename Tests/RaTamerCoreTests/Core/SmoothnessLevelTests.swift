import XCTest
@testable import RaTamerCore

final class SmoothnessLevelTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(SmoothnessLevel.min, 0)
        XCTAssertEqual(SmoothnessLevel.max, 100)
        XCTAssertEqual(SmoothnessLevel.defaultValue, 87)
    }

    func testPresetLevelsAndNames() {
        XCTAssertEqual(SmoothnessPreset.native.level, 0)
        XCTAssertEqual(SmoothnessPreset.smooth.level, 35)
        XCTAssertEqual(SmoothnessPreset.glide.level, 60)
        XCTAssertEqual(SmoothnessPreset.mos.level, 80)
        XCTAssertEqual(SmoothnessPreset.soft.level, 84)
        XCTAssertEqual(SmoothnessPreset.rat.level, 87)
        XCTAssertEqual(SmoothnessPreset.warm.level, 89)
        XCTAssertEqual(SmoothnessPreset.flow.level, 90)
        XCTAssertEqual(SmoothnessPreset.fluid.level, 100)
        XCTAssertEqual(SmoothnessPreset.allCases.count, 9)
        XCTAssertEqual(SmoothnessPreset.rat.displayName, "RaT")
        XCTAssertEqual(SmoothnessPreset.mos.displayName, "Mos")
        XCTAssertEqual(SmoothnessPreset.glide.displayName, "Glide")
    }

    func testPresetInitMatchesExactLevel() {
        XCTAssertEqual(SmoothnessPreset(level: 0), .native)
        XCTAssertEqual(SmoothnessPreset(level: 80), .mos)
        XCTAssertEqual(SmoothnessPreset(level: 87), .rat)
        XCTAssertNil(SmoothnessPreset(level: 55))
    }

    func testClampsOutOfRange() {
        XCTAssertEqual(SmoothnessLevel.clamped(-10), 0)
        XCTAssertEqual(SmoothnessLevel.clamped(150), 100)
        XCTAssertEqual(SmoothnessLevel.clamped(50), 50)
    }

    func testAnchorValues() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(35), 2.5, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(60), 1.6, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(80), 1.2, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.maxBoost(100), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(60), 0.85, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(0), 48, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(80), 115, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(100), 165, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.smoothFraction(90), 0.12, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.glideStopThreshold(80), 0.5, accuracy: 0.0001)
    }

    func testInterpolationBetweenAnchors() {
        XCTAssertEqual(SmoothnessLevel.maxBoost(17.5), 1.75, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.momentumDecay(17.5), 0.79, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(70), 102.5, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.smoothFraction(85), 0.1283, accuracy: 0.0001)
        XCTAssertEqual(SmoothnessLevel.pixelsPerNotch(95), 152.5, accuracy: 0.0001)
    }

    func testAnchorsAreMonotonic() {
        let levels = SmoothnessLevel.anchors.map(\.level)
        XCTAssertEqual(levels, levels.sorted(), "levels must be ascending, got \(levels)")
        let pixelsPerNotch = SmoothnessLevel.anchors.map(\.pixelsPerNotch)
        XCTAssertEqual(pixelsPerNotch, pixelsPerNotch.sorted(),
                       "pixelsPerNotch must be non-decreasing, got \(pixelsPerNotch)")
        let appliedMaxBoost = SmoothnessLevel.anchors.filter { $0.level >= 35 }.map(\.maxBoost)
        XCTAssertEqual(appliedMaxBoost, appliedMaxBoost.sorted(by: >),
                       "maxBoost must be non-increasing from Smooth (level 35), got \(appliedMaxBoost)")
        let appliedSmoothFraction = SmoothnessLevel.anchors.filter { $0.smoothingEnabled }.map(\.smoothFraction)
        XCTAssertEqual(appliedSmoothFraction, appliedSmoothFraction.sorted(by: >),
                       "smoothFraction must be non-increasing on glide presets, got \(appliedSmoothFraction)")
    }

    func testGlidePresetsHaveInertMomentumDecay() {
        let glideDecays = SmoothnessLevel.anchors
            .filter { !$0.momentumEnabled && $0.smoothingEnabled }
            .map(\.momentumDecay)
        XCTAssertFalse(glideDecays.isEmpty, "expected at least one glide preset")
        XCTAssertEqual(Set(glideDecays), [0.85],
                       "glide presets must share the inert momentumDecay 0.85, got \(glideDecays)")
    }

    func testBooleanNearestAnchor() {
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(0))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(17))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(17.5))
        XCTAssertTrue(SmoothnessLevel.momentumEnabled(40))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(47.5))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(60))
        XCTAssertFalse(SmoothnessLevel.momentumEnabled(100))
        XCTAssertFalse(SmoothnessLevel.smoothingEnabled(0))
        XCTAssertFalse(SmoothnessLevel.smoothingEnabled(47))
        XCTAssertTrue(SmoothnessLevel.smoothingEnabled(47.5))
        XCTAssertTrue(SmoothnessLevel.smoothingEnabled(100))
    }

    func testSmoothingStartLevel() {
        XCTAssertEqual(SmoothnessLevel.smoothingStartLevel, 47.5, accuracy: 0.0001)
        XCTAssertFalse(SmoothnessLevel.smoothingEnabled(47))
        XCTAssertTrue(SmoothnessLevel.smoothingEnabled(47.5))
    }

    func testParametersDerivesFullSet() {
        let p = SmoothnessLevel.parameters(level: 80, multiplier: 8, invert: true)
        XCTAssertEqual(p.multiplier, 8)
        XCTAssertEqual(p.invert, true)
        XCTAssertFalse(p.momentumEnabled)
        XCTAssertTrue(p.smoothingEnabled)
        XCTAssertEqual(p.pixelsPerNotch, 115, accuracy: 0.0001)
        XCTAssertEqual(p.maxBoost, 1.2, accuracy: 0.0001)
        XCTAssertEqual(p.smoothFraction, 0.13, accuracy: 0.0001)
        XCTAssertEqual(p.glideStopThreshold, 0.5, accuracy: 0.0001)
        XCTAssertEqual(p.bounceDamping, 0.15, accuracy: 0.0001)
        XCTAssertEqual(p.reversalConfirmation, 3)
        XCTAssertEqual(p.feedGapTimeout, 0.08, accuracy: 0.0001)
        XCTAssertEqual(p.accelerationWindow, 0.05, accuracy: 0.0001)
        XCTAssertEqual(p.momentumStopThreshold, 0.1, accuracy: 0.0001)
        XCTAssertEqual(p.directionThreshold, 1.0, accuracy: 0.0001)
    }
}
