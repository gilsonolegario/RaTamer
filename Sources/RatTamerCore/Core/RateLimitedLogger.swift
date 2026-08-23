import Foundation

/// Thread-safe rate limiter for diagnostics logs.
///
/// Logging from the button loop and the main thread can race on the "last log"
/// timestamp. This serializes the check-and-mark so at most one message passes
/// per `interval`, no matter how many threads call it.
public final class RateLimitedLogger {
    private let lock = NSLock()
    private let interval: TimeInterval
    private var lastLog = Date.distantPast

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// True if the caller may log now; at most one true per `interval`.
    public func shouldLog() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(lastLog) >= interval else { return false }
        lastLog = now
        return true
    }
}
