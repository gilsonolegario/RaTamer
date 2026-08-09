import Foundation
@testable import RatTamerCore

final class MockHIDDevice: HIDDevice {
    var writeLog: [[UInt8]] = []
    private let mailbox = HIDReportMailbox(capacity: 64)
    var onWrite: (([UInt8]) -> [UInt8]?)?
    var onRemoved: (() -> Void)?
    var productName: String?
    private(set) var closeCalled = false
    private(set) var closeCount = 0

    /// Mirrors the real wrapper: seeded reports go through the exact same
    /// FIFO mailbox the production wrapper uses.
    var queuedReads: [[UInt8]] {
        get { mailbox.snapshot() }
        set { mailbox.replaceAll(newValue) }
    }

    func close() {
        closeCalled = true
        closeCount += 1
    }

    func write(_ bytes: [UInt8]) throws {
        writeLog.append(bytes)
        if let response = onWrite?(bytes) {
            mailbox.enqueue(response)
        }
    }

    func read(timeout: TimeInterval) throws -> [UInt8]? {
        mailbox.read(timeout: timeout)
    }

    func readForRequest(timeout: TimeInterval) throws -> [UInt8]? {
        mailbox.readForRequest(timeout: timeout)
    }

    func beginRequest() {
        mailbox.beginRequest()
    }

    func endRequest() {
        mailbox.endRequest()
    }
}
