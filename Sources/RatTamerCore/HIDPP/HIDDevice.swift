import Foundation

public protocol HIDDevice: AnyObject {
    func write(_ bytes: [UInt8]) throws
    var productName: String? { get }
    func read(timeout: TimeInterval) throws -> [UInt8]?
    /// Reads a report from the FIFO mailbox without consulting the in-flight
    /// request gate. Used by `HIDPPSession.request` so a pending synchronous
    /// request never blocks on its own gate.
    func readForRequest(timeout: TimeInterval) throws -> [UInt8]?
    /// Marks the start of a synchronous feature request. **Exclusive**: waits
    /// until no other request is in flight, so concurrent requests cannot steal
    /// each other's replies. While a request is in flight, `read(timeout:)`
    /// must not consume reports so the monitor loop cannot steal its reply.
    func beginRequest()
    /// Marks the end of a synchronous feature request, releasing ownership so
    /// the next queued request (or the gated monitor loop) can proceed.
    func endRequest()
    /// Releases the underlying device (unregisters callbacks, stops the read
    /// loop, closes the IOKit handle). No-op for mock/stateless devices.
    func close()
}

public extension HIDDevice {
    var productName: String? { nil }

    func readForRequest(timeout: TimeInterval) throws -> [UInt8]? {
        try read(timeout: timeout)
    }

    func beginRequest() {}

    func endRequest() {}

    func close() {}
}
