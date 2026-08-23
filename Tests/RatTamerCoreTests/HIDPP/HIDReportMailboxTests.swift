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

    func testReplaceAllTruncatesToCapacity() {
        let mailbox = HIDReportMailbox(capacity: 2)
        mailbox.replaceAll([[1], [2], [3], [4]])
        XCTAssertEqual(mailbox.snapshot(), [[3], [4]])
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

    func testWakeUnblocksBlockedRead() {
        let mailbox = HIDReportMailbox(capacity: 16)
        let readDone = DispatchSemaphore(value: 0)
        var resultBox: [UInt8]?
        let thread = Thread {
            resultBox = mailbox.read(timeout: .greatestFiniteMagnitude)
            readDone.signal()
        }
        thread.name = "test.wake"
        thread.start()
        usleep(50_000)
        mailbox.wake()
        XCTAssertEqual(readDone.wait(timeout: .now() + 1.0), .success)
        XCTAssertNil(resultBox)
    }

    func testWakeConsumesPendingReportsAndBlocksLaterReads() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.enqueue([1])
        mailbox.wake()
        XCTAssertNil(mailbox.read(timeout: 0))
        mailbox.enqueue([2])
        XCTAssertNil(mailbox.read(timeout: 0))
    }

    func testBeginRequestIsExclusive() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.beginRequest()
        let atGate = DispatchSemaphore(value: 0)
        let acquired = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            atGate.signal()
            mailbox.beginRequest()
            acquired.signal()
        }
        atGate.wait()
        XCTAssertEqual(acquired.wait(timeout: .now() + 0.1), .timedOut)
        mailbox.endRequest()
        XCTAssertEqual(acquired.wait(timeout: .now() + 1.0), .success)
        mailbox.endRequest()
    }

    func testBeginRequestTimesOutWhenOwnershipHeld() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.beginRequest()
        XCTAssertFalse(mailbox.beginRequest(timeout: 0.1))
        XCTAssertNil(mailbox.read(timeout: 0), "gate must still be held by the first request")
        mailbox.endRequest()
        XCTAssertTrue(mailbox.beginRequest(timeout: 0.1))
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

    func testTakeBufferReturnsEmptyReusableBuffer() {
        let mailbox = HIDReportMailbox(capacity: 16)
        var buf = mailbox.takeBuffer()
        XCTAssertTrue(buf.isEmpty)
        buf.append(contentsOf: Array(repeating: UInt8(7), count: 40))
        XCTAssertEqual(buf.count, 40)
    }

    func testEnqueueReadRecycleCycle() {
        let mailbox = HIDReportMailbox(capacity: 16)
        var buf = mailbox.takeBuffer()
        buf.append(contentsOf: Array(repeating: UInt8(9), count: 20))
        mailbox.enqueue(buf)
        var out = mailbox.read(timeout: 0)
        XCTAssertEqual(out?.count, 20)
        XCTAssertTrue(out?.allSatisfy { $0 == 9 } == true)
        mailbox.recycle(&out!)
        XCTAssertEqual(mailbox.pooledBufferCount, 1)
    }

    func testRecycleBoundsPoolToCapacity() {
        let mailbox = HIDReportMailbox(capacity: 4)
        var held: [[UInt8]] = []
        for _ in 0..<6 {
            var buf = mailbox.takeBuffer()
            buf.append(contentsOf: [1, 2, 3])
            mailbox.enqueue(buf)
            held.append(mailbox.read(timeout: 0)!)
        }
        for i in 0..<6 {
            mailbox.recycle(&held[i])
        }
        XCTAssertEqual(mailbox.pooledBufferCount, 4)
    }
}
