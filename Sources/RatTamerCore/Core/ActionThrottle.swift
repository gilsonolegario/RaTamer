import Foundation

/// Loop guard for input actions.
///
/// The firmware (or a desynced HID++ report stream) can deliver the same press
/// repeatedly without a matching release. Posting a synthesized event for each
/// one floods WindowServer with rejected events when Accessibility is missing,
/// which froze the UI. This throttle (1) rejects a press while the control is
/// already pressed and (2) caps how often a key can fire, as a safety net.
public final class ActionThrottle {
    private let lock = NSLock()
    private let minInterval: TimeInterval
    private let holdTimeout: TimeInterval
    private var lastFired: [String: TimeInterval] = [:]
    private var active: Set<String> = []
    private var heldSince: [String: TimeInterval] = [:]

    public init(minInterval: TimeInterval, holdTimeout: TimeInterval = 60) {
        self.minInterval = minInterval
        self.holdTimeout = holdTimeout
    }

    /// True only if `key` is not already held. Returns true (and marks it held)
    /// on the first acquire, false for every acquire until `release(key)`.
    /// If the firmware loses the release (a stuck press), the key auto-releases
    /// after `holdTimeout` so future presses are not blocked forever.
    public func acquire(_ key: String, now: TimeInterval = Date().timeIntervalSinceReferenceDate) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if active.contains(key) {
            guard let since = heldSince[key], now - since >= holdTimeout else { return false }
            active.remove(key)
            heldSince.removeValue(forKey: key)
        }
        active.insert(key)
        heldSince[key] = now
        return true
    }

    public func release(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        active.remove(key)
        heldSince.removeValue(forKey: key)
    }

    /// True if `key` may fire now. A second fire within `minInterval` is
    /// suppressed. Safe to call from any thread.
    public func shouldFire(_ key: String, now: TimeInterval = Date().timeIntervalSinceReferenceDate) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let last = lastFired[key], now - last < minInterval {
            return false
        }
        lastFired[key] = now
        return true
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        lastFired.removeAll()
        active.removeAll()
        heldSince.removeAll()
    }
}
