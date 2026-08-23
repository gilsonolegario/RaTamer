import ApplicationServices
import Foundation

enum Permissions {
    private static let lock = NSLock()
    private static let cacheTTL: TimeInterval = 0.5
    private static var cachedTrusted = false
    private static var cachedAt = Date.distantPast

    static func isAccessibilityTrusted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(cachedAt) < cacheTTL else {
            let value = AXIsProcessTrusted()
            cachedTrusted = value
            cachedAt = now
            return value
        }
        return cachedTrusted
    }

    static func requestAccessibility() {
        lock.lock()
        cachedAt = .distantPast
        lock.unlock()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
