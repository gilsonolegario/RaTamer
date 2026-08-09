import Foundation

public enum ProFeature: String, CaseIterable, Sendable {
    case gestures
    case smartShift
    case runShortcut
    case profiles
}

/// Persists the user's license key. Uses an injectable defaults store so tests
/// never touch the real one (same pattern as `OnboardingGate`).
public enum LicenseKeyStore {
    public static var userDefaults: UserDefaults = .standard
    public static let key = "rattamer.licenseKey"

    public static func load() -> String? {
        userDefaults.string(forKey: key)
    }

    public static func save(_ value: String) {
        userDefaults.set(value, forKey: key)
    }

    public static func clear() {
        userDefaults.removeObject(forKey: key)
    }
}
