import XCTest
@testable import RatTamerCore

final class HIDReportMailboxTests: XCTestCase {
    func testFifoOrder() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.enqueue([1])
        mailbox.enqueue([2])
        mailbox.enqueue([3])
        XCTAssertEqual(mailbox.readForRequest(timeout: 0), [1])
        XCTAssertEqual(mailbox.readForRequest(timeout: 0), [2])
        XCTAssertEqual(mailbox.readForRequest(timeout: 0), [3])
    }

    func testCapacityDropsOldest() {
        let mailbox = HIDReportMailbox(capacity: 2)
        mailbox.enqueue([1])
        mailbox.enqueue([2])
        mailbox.enqueue([3])
        XCTAssertEqual(mailbox.snapshot(), [[2], [3]])
    }

    func testReadIsGatedWhileRequestInFlight() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.beginRequest()
        mailbox.enqueue([1])
        XCTAssertNil(mailbox.read(timeout: 0))
        mailbox.endRequest()
        XCTAssertEqual(mailbox.read(timeout: 0), [1])
    }

    func testReadForRequestIgnoresGate() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.beginRequest()
        mailbox.enqueue([1])
        XCTAssertEqual(mailbox.readForRequest(timeout: 0), [1])
        mailbox.endRequest()
    }

    func testReadForRequestTimesOutWhenEmpty() {
        let mailbox = HIDReportMailbox(capacity: 16)
        XCTAssertNil(mailbox.readForRequest(timeout: 0.05))
    }

    func testBeginRequestIsExclusive() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.beginRequest()
        let exp = expectation(description: "second owner waits")
        let acquired = expectation(description: "second owner acquired")
        DispatchQueue.global().async {
            mailbox.beginRequest()
            exp.fulfill()
            acquired.fulfill()
        }
        usleep(50_000)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: 0.1), .timedOut)
        mailbox.endRequest()
        wait(for: [acquired], timeout: 1.0)
        mailbox.endRequest()
    }

    func testConcurrentProducerConsumerDeliversAll() {
        let mailbox = HIDReportMailbox(capacity: 16)
        let count = 8
        let producer = DispatchQueue(label: "test.hidpp.producer")
        producer.async {
            for i in 0..<count {
                mailbox.enqueue([UInt8(i)])
            }
        }
        var received = 0
        for _ in 0..<count {
            if mailbox.readForRequest(timeout: 1.0) != nil {
                received += 1
            }
        }
        XCTAssertEqual(received, count)
    }
}