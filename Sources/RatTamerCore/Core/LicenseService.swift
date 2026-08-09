import Foundation

public final class LicenseService {
    public enum State: Equatable {
        case unlicensed
        case validating
        case active
        case offlineExpired
        case invalid
    }

    public static let cacheWindow: TimeInterval = 30 * 24 * 60 * 60
    static let lastValidatedKey = "rattamer.license.lastValidatedAt"

    private let verifier: any LicenseVerifying
    private let defaults: UserDefaults
    private let keyStore: LicenseKeyStore.Type
    private var _state: State = .unlicensed
    private let lock = NSLock()

    public var onStateChange: ((State) -> Void)?

    public init(verifier: any LicenseVerifying,
                defaults: UserDefaults = .standard,
                keyStore: LicenseKeyStore.Type = LicenseKeyStore.self) {
        self.verifier = verifier
        self.defaults = defaults
        self.keyStore = keyStore
        if keyStore.load() != nil {
            _state = isCacheFresh() ? .active : .offlineExpired
        }
    }

    public var state: State {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public var storedKey: String? {
        keyStore.load()
    }

    public func isPro(_ feature: ProFeature) -> Bool {
        state == .active
    }

    public func submit(key: String) async -> State {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return state }
        keyStore.save(trimmed)
        return await validate()
    }

    public func validate() async -> State {
        setState(.validating)
        guard let key = storedKey else {
            setState(.unlicensed)
            return state
        }
        let result: LicenseVerification
        do {
            result = try await verifier.verify(licenseKey: key)
        } catch {
            guard storedKey == key else { return state }
            if isCacheFresh() {
                setState(.active)
            } else {
                setState(.offlineExpired)
            }
            return state
        }
        guard storedKey == key else { return state }
        if result.success {
            defaults.set(Date(), forKey: Self.lastValidatedKey)
            setState(.active)
        } else {
            keyStore.clear()
            defaults.removeObject(forKey: Self.lastValidatedKey)
            setState(.invalid)
        }
        return state
    }

    public func clear() {
        keyStore.clear()
        defaults.removeObject(forKey: Self.lastValidatedKey)
        setState(.unlicensed)
    }

    private func isCacheFresh() -> Bool {
        guard let date = defaults.object(forKey: Self.lastValidatedKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(date) < Self.cacheWindow
    }

    private func setState(_ newState: State) {
        lock.lock()
        let changed = _state != newState
        _state = newState
        lock.unlock()
        if changed {
            onStateChange?(newState)
        }
    }
}

public extension LicenseService {
    static let productID = "rattamer-pro"
    static var shared = LicenseService(
        verifier: GumroadLicenseClient(productID: productID)
    )
}
