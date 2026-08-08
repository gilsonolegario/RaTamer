import XCTest
@testable import RatTamerCore

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
}
