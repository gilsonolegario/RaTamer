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
    private let capacity: Int

    init(capacity: Int = 16) {
        self.capacity = capacity
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

    func read(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
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

    func beginRequest() {
        condition.lock()
        while activeRequests > 0 {
            condition.wait()
        }
        activeRequests = 1
        condition.broadcast()
        condition.unlock()
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