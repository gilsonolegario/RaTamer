import XCTest
@testable import RaTamerCore

final class VolumeControllerTests: XCTestCase {
    func testClampedVolumeStaysWithinBounds() {
        XCTAssertEqual(VolumeController.clamped(volume: 0.5, plus: 0.10), 0.6, accuracy: 0.0001)
        XCTAssertEqual(VolumeController.clamped(volume: 0.95, plus: 0.10), 1.0, accuracy: 0.0001)
        XCTAssertEqual(VolumeController.clamped(volume: 0.02, plus: -0.03), 0.0, accuracy: 0.0001)
        XCTAssertEqual(VolumeController.clamped(volume: 0.30, plus: -0.10), 0.20, accuracy: 0.0001)
    }

    func testScalarStepsMatchAppleScriptTenAndThreePercent() {
        // Old AppleScript: output volume (0-100) ±10 / ±3 professional steps.
        // Scalar space is 0-1, so 10/100 = 0.10 and 3/100 = 0.03.
        XCTAssertEqual(VolumeStep.normal.rawValue, 0.10, accuracy: 0.0001)
        XCTAssertEqual(VolumeStep.small.rawValue, 0.03, accuracy: 0.0001)
    }
}