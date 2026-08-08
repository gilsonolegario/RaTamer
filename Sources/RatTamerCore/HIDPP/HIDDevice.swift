import Foundation

public protocol HIDDevice: AnyObject {
    func write(_ bytes: [UInt8]) throws
    func read(timeout: TimeInterval) throws -> [UInt8]?
    /// Reads a report from the single-slot mailbox without consulting the
    /// in-flight request gate. Used by `HIDPPSession.request` so a pending
    /// synchronous request never blocks on its own gate.
    func readForRequest(timeout: TimeInterval) throws -> [UInt8]?
    /// Marks the start/end of a synchronous feature request. While a request
    /// is in flight, `read(timeout:)` must not consume reports so the monitor
    /// loop cannot steal the request's reply.
    func beginRequest()
    func endRequest()
}

public extension HIDDevice {
    func readForRequest(timeout: TimeInterval) throws -> [UInt8]? {
        try read(timeout: timeout)
    }

    func beginRequest() {}

    func endRequest() {}
}
