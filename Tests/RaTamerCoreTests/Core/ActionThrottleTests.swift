import XCTest
@testable import RaTamerCore

final class ActionThrottleTests: XCTestCase {
    private var throttle: ActionThrottle!

    override func setUp() {
        super.setUp()
        throttle = ActionThrottle(minInterval: 0.25)
    }

    func testFirstAcquireAllows() {
        XCTAssertTrue(throttle.acquire("a"))
    }

    func testAcquireRejectsWhileHeld() {
        XCTAssertTrue(throttle.acquire("a"))
        XCTAssertFalse(throttle.acquire("a"))
    }

    func testReleaseAllowsReacquire() {
        XCTAssertTrue(throttle.acquire("a"))
        throttle.release("a")
        XCTAssertTrue(throttle.acquire("a"))
    }

    func testAcquireKeysAreIndependent() {
        XCTAssertTrue(throttle.acquire("a"))
        XCTAssertTrue(throttle.acquire("b"))
        XCTAssertFalse(throttle.acquire("a"))
    }

    func testFirstFireIsAllowed() {
        XCTAssertTrue(throttle.shouldFire("k", now: 1000))
    }

    func testRepeatedFireWithinIntervalIsSuppressed() {
        XCTAssertTrue(throttle.shouldFire("k", now: 1000))
        XCTAssertFalse(throttle.shouldFire("k", now: 1000.1))
    }

    func testFireAfterIntervalIsAllowed() {
        XCTAssertTrue(throttle.shouldFire("k", now: 1000))
        XCTAssertTrue(throttle.shouldFire("k", now: 1000.26))
    }

    func testFireKeysAreIndependent() {
        XCTAssertTrue(throttle.shouldFire("k1", now: 1000))
        XCTAssertTrue(throttle.shouldFire("k2", now: 1000.1))
        XCTAssertFalse(throttle.shouldFire("k1", now: 1000.1))
    }

    func testResetClearsState() {
        XCTAssertTrue(throttle.acquire("a"))
        XCTAssertTrue(throttle.shouldFire("k", now: 1000))
        throttle.reset()
        XCTAssertTrue(throttle.acquire("a"))
        XCTAssertTrue(throttle.shouldFire("k", now: 1000.1))
    }

    func testAcquireAutoReleasesAfterHoldTimeout() {
        let throttle = ActionThrottle(minInterval: 0.25, holdTimeout: 1.0)
        XCTAssertTrue(throttle.acquire("a", now: 0))
        XCTAssertFalse(throttle.acquire("a", now: 0.9), "rejected before timeout")
        XCTAssertTrue(throttle.acquire("a", now: 1.1), "stuck press auto-releases after timeout")
    }

    func testAcquireRestartsHeldClockAfterRecovery() {
        let throttle = ActionThrottle(minInterval: 0.25, holdTimeout: 1.0)
        _ = throttle.acquire("a", now: 0)
        _ = throttle.acquire("a", now: 1.1)
        XCTAssertFalse(throttle.acquire("a", now: 1.2), "held clock restarts after auto-release")
    }

    func testReleaseClearsHeldClockImmediately() {
        let throttle = ActionThrottle(minInterval: 0.25, holdTimeout: 1.0)
        _ = throttle.acquire("a", now: 0)
        throttle.release("a")
        XCTAssertTrue(throttle.acquire("a", now: 100), "manual release clears held state")
    }

    func testHeldRecoveryIsPerKey() {
        let throttle = ActionThrottle(minInterval: 0.25, holdTimeout: 1.0)
        _ = throttle.acquire("a", now: 0)
        _ = throttle.acquire("b", now: 0.5)
        XCTAssertTrue(throttle.acquire("a", now: 1.1), "a auto-releases after 1.1s held")
        XCTAssertFalse(throttle.acquire("b", now: 1.1), "b held only 0.6s, still locked")
    }
}
