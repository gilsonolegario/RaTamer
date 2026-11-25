import AppKit
import Foundation
import RaTamerCore

struct DPICache: Equatable {
    var values: [UInt16]
    var value: Double
}

final class AppModel: ObservableObject {
    static let shared = AppModel()
    let configStore = ConfigStore(fileURL: ConfigStore.defaultFileURL())
    private(set) var engine: EngineController?
    @Published var config: Config
    @Published var accessibilityTrusted: Bool
    @Published var statusText = "Starting…"
    @Published var isConnected = false
    @Published var isReconnecting = false
    @Published var controls: [ControlInfo] = []
    /// Isolated press state — only views that show pressed indicators observe this.
    let pressMonitor = ButtonPressMonitor()
    @Published var deviceName = "HID++ device"
    @Published var capabilities = DeviceCapabilities(hasReprogrammableControls: false,
                                                     hasBattery: false,
                                                     hasDPI: false,
                                                     hasSmartShift: false)
    @Published var remappingEnabled = true {
        didSet {
            guard remappingEnabled != oldValue else { return }
            engine?.enabled = remappingEnabled
        }
    }
    @Published var dpiCache: DPICache?
    private var activeObserver: NSObjectProtocol?

    private init() {
        self.config = configStore.load()
        self.accessibilityTrusted = Permissions.refreshAccessibilityTrusted()
        self.activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAccessibility()
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    func refreshAccessibility() {
        let trusted = Permissions.refreshAccessibilityTrusted()
        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
        }
        engine?.recheckAccessibility()
    }

    @discardableResult
    func reloadConfig() -> Config {
        let latest = configStore.load()
        if Thread.isMainThread {
            self.config = latest
        } else {
            DispatchQueue.main.async { self.config = latest }
        }
        return latest
    }

    @discardableResult
    func updateConfig(_ transform: (inout Config) -> Void) -> Config {
        let updated = (try? configStore.update(transform)) ?? {
            var copy = configStore.load()
            transform(&copy)
            return copy
        }()
        if Thread.isMainThread {
            self.config = updated
        } else {
            DispatchQueue.main.async { self.config = updated }
        }
        return updated
    }

    func startEngine() {
        let engine = EngineController(configStore: configStore)
        engine.onStatus = { [weak self] text in
            DispatchQueue.main.async { self?.statusText = text }
        }
        engine.onConnectionState = { [weak self, weak engine] state in
            DispatchQueue.main.async {
                guard let self, let engine else { return }
                switch state {
                case .connected:
                    self.isConnected = true
                    self.isReconnecting = false
                    self.deviceName = engine.deviceName
                    self.capabilities = engine.capabilities
                    self.preloadDPI()
                    BatteryMonitor.shared.refresh()
                case .disconnected:
                    self.isConnected = false
                    self.isReconnecting = false
                    self.dpiCache = nil
                    self.pressMonitor.pressed.removeAll()
                    BatteryMonitor.shared.clear()
                case .reconnecting:
                    self.isConnected = false
                    self.isReconnecting = true
                    self.dpiCache = nil
                    self.pressMonitor.pressed.removeAll()
                    BatteryMonitor.shared.clear()
                }
            }
        }
        engine.onControlsChanged = { [weak self] controls in
            DispatchQueue.main.async { self?.controls = controls }
        }
        engine.onButtonEvent = { [weak self] cid in
            DispatchQueue.main.async { self?.pressMonitor.pressed.insert(cid) }
        }
        engine.onButtonReleased = { [weak self] cid in
            DispatchQueue.main.async { self?.pressMonitor.pressed.remove(cid) }
        }
        engine.onDPIChanged = { [weak self] dpi in
            DispatchQueue.main.async {
                guard let self else { return }
                self.config = self.configStore.load()
                if var cache = self.dpiCache {
                    cache.value = Double(dpi)
                    self.dpiCache = cache
                } else {
                    self.preloadDPI()
                }
            }
        }
        let started = engine.start()
        self.engine = engine
        if started {
            preloadDPI()
            BatteryMonitor.shared.refresh()
        }
    }

    func preloadDPI() {
        // Capture the service and stored DPI on the calling (main) thread before
        // hopping to background.
        let service = engine?.dpiService
        let stored = configStore.load().dpiValue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let service else {
                DispatchQueue.main.async { self?.dpiCache = nil }
                return
            }
            let values = (try? service.getSensorDpiList(sensor: 0)) ?? []
            guard values.count > 1 else {
                DispatchQueue.main.async { self?.dpiCache = nil }
                return
            }
            var value = 1000.0
            if let stored {
                value = Double(stored)
            } else if let info = try? service.getSensorDpi(sensor: 0) {
                value = Double(info.dpi)
            }
            let cache = DPICache(values: values, value: value)
            DispatchQueue.main.async { self?.dpiCache = cache }
        }
    }

    func stopEngine() {
        engine?.stop()
    }
}

/// Isolated press state — only views that show pressed indicators observe this,
/// avoiding unnecessary redraws in the rest of the app.
final class ButtonPressMonitor: ObservableObject {
    @Published var pressed = Set<UInt16>()
}
