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
    /// Marks the start of a synchronous feature request with a bounded wait.
    /// Returns false if ownership could not be acquired before `timeout` elapses,
    /// without changing state (the caller should treat it as a failed request).
    func beginRequest(timeout: TimeInterval) -> Bool
    /// Marks the end of a synchronous feature request, releasing ownership so
    /// the next queued request (or the gated monitor loop) can proceed.
    func endRequest()
    /// Wakes a thread blocked in `read(timeout:)` so it returns and stops
    /// consuming from this device. Used at teardown so the monitor loop can
    /// block indefinitely on reports instead of polling. No-op for mocks.
    func wake()
    /// Returns a consumed report's storage to the device's buffer pool so the
    /// hot HID path reuses it. The caller must hold the sole reference
    /// (`inout`) to avoid a copy-on-write allocation. No-op for mocks.
    func recycle(_ bytes: inout [UInt8])
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

    func beginRequest(timeout: TimeInterval) -> Bool { true }

    func endRequest() {}

    func wake() {}

    func recycle(_ bytes: inout [UInt8]) {
        bytes.removeAll(keepingCapacity: false)
    }

    func close() {}
}
