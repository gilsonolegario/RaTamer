import Foundation

/// Exponential backoff schedule for reconnecting to the receiver.
public enum RetryPolicy {
    /// Delay for `attempt` (0-based), doubling each time, capped at `maxDelay`.
    public static func delay(attempt: Int, base: TimeInterval, maxDelay: TimeInterval) -> TimeInterval {
        min(base * pow(2, Double(max(0, attempt))), maxDelay)
    }
}
