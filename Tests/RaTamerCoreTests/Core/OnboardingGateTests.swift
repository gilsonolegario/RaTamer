import Foundation
import XCTest
@testable import RaTamerCore

final class OnboardingGateTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.onboarding.\(UUID().uuidString)")
        OnboardingGate.userDefaults = defaults
    }

    override func tearDown() {
        OnboardingGate.userDefaults = .standard
        super.tearDown()
    }

    func testShowsOnFirstRun() {
        XCTAssertTrue(OnboardingGate.shouldShow)
    }

    func testHiddenAfterComplete() {
        OnboardingGate.complete()
        XCTAssertFalse(OnboardingGate.shouldShow)
    }

    func testShowsAgainAfterReset() {
        OnboardingGate.complete()
        OnboardingGate.reset()
        XCTAssertTrue(OnboardingGate.shouldShow)
    }
}
