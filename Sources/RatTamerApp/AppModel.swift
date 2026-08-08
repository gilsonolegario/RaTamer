import Foundation
import RatTamerCore

final class AppModel: ObservableObject {
    static let shared = AppModel()
    let configStore = ConfigStore(fileURL: ConfigStore.defaultFileURL())
    private(set) var engine: EngineController?
    @Published var statusText = "Starting…"
    @Published var isConnected = false
    @Published var isReconnecting = false
    @Published var controls: [ControlInfo] = []
    @Published var pressed = Set<UInt16>()
    @Published var remappingEnabled = true {
        didSet {
            guard remappingEnabled != oldValue else { return }
            engine?.enabled = remappingEnabled
        }
    }
    @Published var deviceName = "HID++ device"
    @Published var capabilities = DeviceCapabilities(hasReprogrammableControls: false,
                                                     hasBattery: false,
                                                     hasDPI: false,
                                                     hasSmartShift: false)

    private init() {}

    func startEngine() {
        let engine = EngineController(configStore: configStore)
        engine.onStatus = { [weak self] text in
            DispatchQueue.main.async { self?.statusText = text }
        }
        engine.onConnectionState = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .connected:
                    self?.isConnected = true
                    self?.isReconnecting = false
                    self?.deviceName = engine.deviceName
                    self?.capabilities = engine.capabilities
                case .disconnected:
                    self?.isConnected = false
                    self?.isReconnecting = false
                case .reconnecting:
                    self?.isConnected = false
                    self?.isReconnecting = true
                }
            }
        }
        engine.onControlsChanged = { [weak self] controls in
            DispatchQueue.main.async { self?.controls = controls }
        }
        engine.onButtonEvent = { [weak self] cid in
            DispatchQueue.main.async { self?.pressed.insert(cid) }
        }
        engine.onButtonReleased = { [weak self] cid in
            DispatchQueue.main.async { self?.pressed.remove(cid) }
        }
        _ = engine.start()
        self.engine = engine
    }

    func stopEngine() {
        engine?.stop()
    }
}
