import Foundation
@testable import RatTamerCore

final class MockHIDDevice: HIDDevice {
    var writeLog: [[UInt8]] = []
    var queuedReads: [[UInt8]] = []
    var onWrite: (([UInt8]) -> [UInt8]?)?
    var onRemoved: (() -> Void)?
    var productName: String?
    var inFlightRequests = 0
    private(set) var closeCalled = false
    private(set) var closeCount = 0

    func close() {
        closeCalled = true
        closeCount += 1
    }

    func write(_ bytes: [UInt8]) throws {
        writeLog.append(bytes)
        if let response = onWrite?(bytes) {
            queuedReads.append(response)
        }
    }

    /// Mirrors the real wrapper: while a synchronous request is in flight,
    /// `read` must not consume reports so it cannot steal the request's reply.
    func read(timeout: TimeInterval) throws -> [UInt8]? {
        guard inFlightRequests == 0 else { return nil }
        return readFromQueue()
    }

    func readForRequest(timeout: TimeInterval) throws -> [UInt8]? {
        readFromQueue()
    }

    func beginRequest() {
        inFlightRequests += 1
    }

    func endRequest() {
        inFlightRequests -= 1
    }

    private func readFromQueue() -> [UInt8]? {
        guard !queuedReads.isEmpty else { return nil }
        return queuedReads.removeFirst()
    }
}
