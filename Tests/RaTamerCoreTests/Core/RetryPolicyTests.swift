import XCTest
@testable import RaTamerCore

final class RetryPolicyTests: XCTestCase {
    func testDelayStartsAtBase() {
        XCTAssertEqual(RetryPolicy.delay(attempt: 0, base: 2, maxDelay: 30), 2)
    }

    func testDelayGrowsExponentially() {
        XCTAssertEqual(RetryPolicy.delay(attempt: 1, base: 2, maxDelay: 30), 4)
        XCTAssertEqual(RetryPolicy.delay(attempt: 2, base: 2, maxDelay: 30), 8)
        XCTAssertEqual(RetryPolicy.delay(attempt: 3, base: 2, maxDelay: 30), 16)
    }

    func testDelayCapsAtMax() {
        XCTAssertEqual(RetryPolicy.delay(attempt: 10, base: 2, maxDelay: 30), 30)
        XCTAssertEqual(RetryPolicy.delay(attempt: 0, base: 2, maxDelay: 1.5), 1.5)
    }
}
