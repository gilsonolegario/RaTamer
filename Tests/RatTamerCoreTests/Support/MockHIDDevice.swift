import Foundation
@testable import RatTamerCore

final class MockHIDDevice: HIDDevice {
    var writeLog: [[UInt8]] = []
    var queuedReads: [[UInt8]] = []
    var onWrite: (([UInt8]) -> [UInt8]?)?

    func write(_ bytes: [UInt8]) throws {
        writeLog.append(bytes)
        if let response = onWrite?(bytes) {
            queuedReads.append(response)
        }
    }

    func read(timeout: TimeInterval) throws -> [UInt8]? {
        guard !queuedReads.isEmpty else { return nil }
        return queuedReads.removeFirst()
    }
}
