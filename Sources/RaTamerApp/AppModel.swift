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

    private init() {}

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
                case .disconnected:
                    self.isConnected = false
                    self.isReconnecting = false
                    self.dpiCache = nil
                case .reconnecting:
                    self.isConnected = false
                    self.isReconnecting = true
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
        _ = engine.start()
        self.engine = engine
        preloadDPI()
    }

    func preloadDPI() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let service = self.engine?.dpiService else { return }
            let values = (try? service.getSensorDpiList(sensor: 0)) ?? []
            guard values.count > 1 else { return }
            var value = 1000.0
            let stored = self.configStore.load().dpiValue
            if let stored {
                value = Double(stored)
            } else if let info = try? service.getSensorDpi(sensor: 0) {
                value = Double(info.dpi)
            }
            let cache = DPICache(values: values, value: value)
            DispatchQueue.main.async { self.dpiCache = cache }
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
