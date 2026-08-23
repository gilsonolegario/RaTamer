import Foundation

/// Thread-safe FIFO report mailbox with request-ownership semantics.
///
/// The monitor loop reads via `read(timeout:)`, which refuses to consume while
/// a synchronous request is in flight (`activeRequests > 0`) so the loop cannot
/// steal a request's reply. Requests read via `readForRequest(timeout:)`,
/// which ignores the gate. `beginRequest()` is exclusive — it waits until no
/// other request holds ownership — so two concurrent requests can never steal
/// each other's replies. Reports beyond `capacity` drop the oldest entry.
final class HIDReportMailbox {
    private let condition = NSCondition()
    private var reports: [[UInt8]] = []
    private var activeRequests = 0
    private var wakePending = false
    private let capacity: Int
    private static let bufferSize = 64
    private var freeBuffers: [[UInt8]] = []

    init(capacity: Int = 16) {
        self.capacity = capacity
    }

    /// Hands out a reusable buffer (empty, capacity ≥ `bufferSize`) for the
    /// producer to fill, so the hot report path reuses storage instead of
    /// allocating a fresh array per HID report.
    func takeBuffer() -> [UInt8] {
        condition.lock()
        defer { condition.unlock() }
        if let buf = freeBuffers.popLast() { return buf }
        var buf = [UInt8]()
        buf.reserveCapacity(Self.bufferSize)
        return buf
    }

    /// Returns a consumed report's storage to the pool. The caller must hold
    /// the sole reference (`inout`) so the clear happens in place, without a
    /// copy-on-write allocation.
    func recycle(_ bytes: inout [UInt8]) {
        condition.lock()
        defer { condition.unlock() }
        bytes.removeAll(keepingCapacity: true)
        if freeBuffers.count < capacity {
            freeBuffers.append(bytes)
        }
    }

    /// Number of buffers currently pooled, exposed for tests.
    var pooledBufferCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return freeBuffers.count
    }

    func enqueue(_ bytes: [UInt8]) {
        condition.lock()
        if reports.count >= capacity {
            reports.removeFirst()
        }
        reports.append(bytes)
        condition.broadcast()
        condition.unlock()
    }

    /// Wakes a thread blocked in `read(timeout:)`, making it return nil and
    /// discarding any pending reports so the caller stops consuming from this
    /// mailbox (used when the engine tears down its monitor loop). One-shot
    /// per instance: reconnect builds a fresh device/mailbox.
    func wake() {
        condition.lock()
        wakePending = true
        reports.removeAll()
        condition.broadcast()
        condition.unlock()
    }

    func read(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if wakePending { return nil }
            if activeRequests == 0, !reports.isEmpty {
                return reports.removeFirst()
            }
            if !condition.wait(until: deadline) { return nil }
        }
    }

    func readForRequest(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if !reports.isEmpty {
                return reports.removeFirst()
            }
            if !condition.wait(until: deadline) { return nil }
        }
    }

    /// Acquires exclusive ownership of the request path, blocking until any
    /// current owner releases it via `endRequest()`.
    ///
    /// Not re-entrant: calling `beginRequest()` from a thread that already
    /// holds ownership (e.g. while another `beginRequest()` is in progress on
    /// the same thread) deadlocks. The wrapper's request path never does this.
    func beginRequest(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while activeRequests > 0 {
            if !condition.wait(until: deadline) {
                return false
            }
        }
        activeRequests = 1
        condition.broadcast()
        return true
    }

    func beginRequest() {
        _ = beginRequest(timeout: .greatestFiniteMagnitude)
    }

    func endRequest() {
        condition.lock()
        activeRequests = 0
        condition.broadcast()
        condition.unlock()
    }

    func snapshot() -> [[UInt8]] {
        condition.lock()
        defer { condition.unlock() }
        return reports
    }

    func replaceAll(_ newReports: [[UInt8]]) {
        condition.lock()
        reports = Array(newReports.suffix(capacity))
        condition.broadcast()
        condition.unlock()
    }
}
