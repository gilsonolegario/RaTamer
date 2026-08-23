import Foundation

/// Tracks device presence from periodic ping results. A device is considered
/// disconnected after `failureThreshold` consecutive failures, and reconnected
/// on the next success.
public final class ConnectionWatchdog {
    public var onDisconnected: (() -> Void)?
    public var onReconnected: (() -> Void)?

    public private(set) var isConnected: Bool

    private let failureThreshold: Int
    private let lock = NSLock()
    private var failures = 0

    public init(isConnected: Bool = true, failureThreshold: Int = 3) {
        self.isConnected = isConnected
        self.failureThreshold = max(1, failureThreshold)
    }

    public func report(ok: Bool) {
        lock.lock()
        if ok {
            failures = 0
            if !isConnected {
                isConnected = true
                lock.unlock()
                onReconnected?()
                return
            }
        } else {
            failures += 1
            if isConnected && failures >= failureThreshold {
                isConnected = false
                lock.unlock()
                onDisconnected?()
                return
            }
        }
        lock.unlock()
    }
}
