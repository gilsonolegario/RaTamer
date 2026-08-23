import XCTest
@testable import RatTamerCore

final class SmoothScrollSettingsTests: XCTestCase {
    func testLevelOnlyDerivesLevelParams() {
        let settings = SmoothScrollSettings(level: 50, advanced: nil, multiplier: 8, invert: false)
        let p = settings.parameters
        XCTAssertEqual(p.maxBoost, SmoothnessLevel.maxBoost(50))
        XCTAssertEqual(p.momentumDecay, SmoothnessLevel.momentumDecay(50))
        XCTAssertEqual(p.momentumEnabled, SmoothnessLevel.momentumEnabled(50))
        XCTAssertEqual(p.multiplier, 8)
        XCTAssertFalse(settings.isCustom)
    }

    func testAdvancedWinsAndIsCustomWhenDiverging() {
        let advanced = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: true, invert: false,
                                                 maxBoost: 4.2, momentumDecay: 0.9)
        let settings = SmoothScrollSettings(level: 50, advanced: advanced, multiplier: 8, invert: false)
        let p = settings.parameters
        XCTAssertEqual(p.maxBoost, 4.2)
        XCTAssertEqual(p.momentumDecay, 0.9)
        XCTAssertTrue(settings.isCustom)
    }

    func testMultipletAndInvertAlwaysOverwritten() {
        let advanced = ScrollSmoother.Parameters(multiplier: 1, momentumEnabled: true, invert: true,
                                                 maxBoost: 3.0, momentumDecay: 0.85)
        let settings = SmoothScrollSettings(level: 50, advanced: advanced, multiplier: 8, invert: false)
        let p = settings.parameters
        XCTAssertEqual(p.multiplier, 8)
        XCTAssertEqual(p.invert, false)
    }

    func testNilLevelDefaultsToDefaultLevelWhenNoAdvanced() {
        let settings = SmoothScrollSettings(level: nil, advanced: nil, multiplier: 8, invert: false)
        XCTAssertEqual(settings.parameters.maxBoost, SmoothnessLevel.maxBoost(SmoothnessLevel.defaultValue))
        XCTAssertEqual(settings.parameters.momentumDecay, SmoothnessLevel.momentumDecay(SmoothnessLevel.defaultValue))
        XCTAssertEqual(settings.parameters.momentumEnabled, SmoothnessLevel.momentumEnabled(SmoothnessLevel.defaultValue))
        XCTAssertFalse(settings.isCustom)
    }

    func testNilLevelWithAdvancedIsCustom() {
        let advanced = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: false, invert: false,
                                                 maxBoost: 4.2)
        let settings = SmoothScrollSettings(level: nil, advanced: advanced, multiplier: 8, invert: false)
        XCTAssertTrue(settings.isCustom)
        XCTAssertEqual(settings.parameters.maxBoost, 4.2)
    }

    func testIsCustomFalseWhenAdvancedMatchesDerived() {
        let derived = SmoothnessLevel.parameters(level: 70, multiplier: 8, invert: false)
        let settings = SmoothScrollSettings(level: 70, advanced: derived, multiplier: 8, invert: false)
        XCTAssertFalse(settings.isCustom)
    }

    func testIsCustomTrueWhenGlideDiverges() {
        let advanced = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: false, invert: false,
                                                 maxBoost: 1.5, momentumDecay: 0.85,
                                                 pixelsPerNotch: 150, smoothingEnabled: true)
        let settings = SmoothScrollSettings(level: 70, advanced: advanced, multiplier: 8, invert: false)
        XCTAssertTrue(settings.isCustom)
    }

    func testIsCustomTrueWhenSmoothFractionOrGlideStopDiverges() {
        let advanced = ScrollSmoother.Parameters(multiplier: 8, momentumEnabled: false, invert: false,
                                                 maxBoost: 1.5, momentumDecay: 0.85,
                                                 pixelsPerNotch: 100, smoothingEnabled: true,
                                                 smoothFraction: 0.09, glideStopThreshold: 0.8)
        let settings = SmoothScrollSettings(level: 70, advanced: advanced, multiplier: 8, invert: false)
        XCTAssertTrue(settings.isCustom)
    }
}