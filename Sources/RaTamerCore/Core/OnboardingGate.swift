import Foundation

/// Decides when the first-run welcome should appear and records completion.
/// Uses an injectable defaults store so tests never touch the real one.
public enum OnboardingGate {
    public static var userDefaults: UserDefaults = .standard
    public static let completedKey = "ratamer.hasCompletedOnboarding"

    public static var shouldShow: Bool {
        !userDefaults.bool(forKey: completedKey)
    }

    public static func complete() {
        userDefaults.set(true, forKey: completedKey)
    }

    public static func reset() {
        userDefaults.removeObject(forKey: completedKey)
    }
}
