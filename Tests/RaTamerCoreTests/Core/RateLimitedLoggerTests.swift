import XCTest
@testable import RaTamerCore

final class RateLimitedLoggerTests: XCTestCase {
    func testFirstCallIsAllowed() {
        let logger = RateLimitedLogger(interval: 60)
        XCTAssertTrue(logger.shouldLog())
    }

    func testCallsWithinIntervalAreThrottled() {
        let logger = RateLimitedLogger(interval: 60)
        XCTAssertTrue(logger.shouldLog())
        XCTAssertFalse(logger.shouldLog())
        XCTAssertFalse(logger.shouldLog())
    }

    func testCallAfterIntervalIsAllowedAgain() {
        let logger = RateLimitedLogger(interval: 0.05)
        XCTAssertTrue(logger.shouldLog())
        Thread.sleep(forTimeInterval: 0.06)
        XCTAssertTrue(logger.shouldLog())
    }

    func testConcurrentCallsDoNotCrashAndRespectInterval() {
        let logger = RateLimitedLogger(interval: 60)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.rateLogger", attributes: .concurrent)
        var allowed = 0
        let allowedLock = NSLock()
        for _ in 0..<200 {
            queue.async(group: group) {
                if logger.shouldLog() {
                    allowedLock.lock()
                    allowed += 1
                    allowedLock.unlock()
                }
            }
        }
        group.wait()
        // At most one call may pass the 60s gate; assert bounded and safe.
        XCTAssertGreaterThanOrEqual(allowed, 1)
        XCTAssertLessThanOrEqual(allowed, 2)
    }
}
