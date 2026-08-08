import AppKit
import Foundation
import RatTamerCore
import os

final class EngineController {
    private static let log = Logger(subsystem: "com.rattamer", category: "engine")
    private let configStore: ConfigStore
    private var session: HIDPPSession?
    private var controlsService: ReprogrammableControls?
    private var monitor: DivertedButtonMonitor?
    private var loopThread: Thread?
    private let deviceIndex: UInt8 = 1
    private let actionEngine = ActionEngine(poster: CGEventPoster())
    private let gestureDetector: GestureDetector
    private var gestureCID: UInt16?
    private var scrollWheelTap: ScrollWheelTap?
    private var smartShiftService: SmartShiftControls?
    private var _dpiService: AdjustableDPI?
    private var _batteryService: BatteryStatus?
    private var _hiResWheelService: HiResWheel?
    private var stopped = false
    private var _enabled = true
    private let enabledLock = NSLock()
    private var cachedConfig: Config
    private let configLock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.rattamer.io")
    private var watchdog: ConnectionWatchdog?
    private var pingTimer: DispatchSourceTimer?
    private static let pingInterval: TimeInterval = 2.0

    var enabled: Bool {
        get {
            enabledLock.lock()
            defer { enabledLock.unlock() }
            return _enabled
        }
        set {
            enabledLock.lock()
            _enabled = newValue
            enabledLock.unlock()
            guard !stopped else { return }
            if newValue {
                ioQueue.async { [weak self] in
                    guard let self, let controlsService = self.controlsService else { return }
                    self.applyAll(controlsService: controlsService)
                }
            } else {
                ioQueue.async { [weak self] in
                    guard let self else { return }
                    self.restoreNativeDiverts()
                }
            }
        }
    }

    var onStatus: ((_ text: String) -> Void)?
    var onButtonEvent: ((_ cid: UInt16) -> Void)?
    var onButtonReleased: ((_ cid: UInt16) -> Void)?
    var onControlsChanged: (([ControlInfo]) -> Void)?
    private(set) var isConnected = false
    private(set) var controls: [ControlInfo] = []
    var dpiService: AdjustableDPI? { _dpiService }
    var batteryStatusService: BatteryStatus? { _batteryService }
    var hiResWheelService: HiResWheel? { _hiResWheelService }

    init(configStore: ConfigStore) {
        self.configStore = configStore
        self.cachedConfig = configStore.load()
        self.gestureDetector = GestureDetector(actionEngine: actionEngine)
        let tap = ScrollWheelTap(
            shouldIntercept: { [weak self] direction in
                guard let self, self.enabled, self.isConnected else { return false }
                return self.hasThumbWheelAction(direction)
            },
            onNotch: { [weak self] direction in
                self?.executeThumbWheelNotch(direction)
            }
        )
        self.scrollWheelTap = tap
    }

    func start() -> Bool {
        stopped = false
        ActionEngine.warmKeyCodeCache()
        do {
            let device = try HIDLocator.openReceiver()
            let session = HIDPPSession(device: device)
            self.session = session
            guard let featureIndex = try session.getFeatureIndex(
                featureID: ReprogrammableControls.featureID, deviceIndex: deviceIndex
            ) else {
                onStatus?("0x1B04 feature not found")
                return false
            }
            let controlsService = ReprogrammableControls(
                session: session, deviceIndex: deviceIndex, featureIndex: featureIndex
            )
            self.controlsService = controlsService
            self.controls = try controlsService.enumerate()
            Self.log.info("start connected: \(self.controls.count) controls, axTrusted=\(Permissions.isAccessibilityTrusted())")
            onControlsChanged?(controls)

            if let smartShiftIndex = try? session.getFeatureIndex(
                featureID: SmartShiftControls.featureID, deviceIndex: deviceIndex
            ) {
                let service = SmartShiftControls(session: session,
                                                 deviceIndex: deviceIndex,
                                                 featureIndex: smartShiftIndex)
                self.smartShiftService = service
            }
            if let dpiIndex = try? session.getFeatureIndex(
                featureID: AdjustableDPI.featureID, deviceIndex: deviceIndex
            ) {
                self._dpiService = AdjustableDPI(session: session,
                                                deviceIndex: deviceIndex,
                                                featureIndex: dpiIndex)
            }
            if let batteryIndex = try? session.getFeatureIndex(
                featureID: BatteryStatus.featureID, deviceIndex: deviceIndex
            ) {
                self._batteryService = BatteryStatus(session: session,
                                                     deviceIndex: deviceIndex,
                                                     featureIndex: batteryIndex)
            }
            if let wheelIndex = try? session.getFeatureIndex(
                featureID: HiResWheel.featureID, deviceIndex: deviceIndex
            ) {
                self._hiResWheelService = HiResWheel(session: session,
                                                     deviceIndex: deviceIndex,
                                                     featureIndex: wheelIndex)
            }

            let monitor = DivertedButtonMonitor(deviceIndex: deviceIndex, featureIndex: featureIndex)
            monitor.onControlPressed = { [weak self] cid in
                self?.handlePress(cid)
            }
            monitor.onControlReleased = { [weak self] cid in
                self?.handleRelease(cid)
            }
            monitor.onRawXY = { [weak self] dx, dy in
                self?.handleRawXY(dx: dx, dy: dy)
            }
            self.monitor = monitor

            refreshConfig()
            applyAll(controlsService: controlsService)
            setupWatchdog()
            startLoopThread(monitor: monitor)
            isConnected = true
            EngineEvents.shared.onConnected?()
            onStatus?("Connected — \(controls.count) controls")
            scrollWheelTap?.start()
            return true
        } catch {
            isConnected = false
            onStatus?("Not connected: \(error)")
            return false
        }
    }

    func applyConfig() {
        refreshConfig()
        ioQueue.async { [weak self] in
            guard let self, let controlsService = self.controlsService, !self.stopped else { return }
            self.applyAll(controlsService: controlsService)
        }
    }

    private func applyAll(controlsService: ReprogrammableControls) {
        applyDiverts(controlsService: controlsService)
        applySwapIfNeeded(controlsService: controlsService)
        if let service = smartShiftService {
            applySmartShiftIfNeeded(service: service)
        }
        if let service = _dpiService {
            applyDPIIfNeeded(service: service)
        }
        if let service = _hiResWheelService {
            applyScrollInversionIfNeeded(service: service)
        }
    }

    func applyAction(_ action: ButtonAction?, forCID cid: UInt16) {
        guard let control = controls.first(where: { $0.cid == cid }), control.isDivertable else { return }
        refreshConfig()
        ioQueue.async { [weak self] in
            guard let self, let controlsService = self.controlsService, !self.stopped else { return }
            try? controlsService.setDiverted(cid: control.cid,
                                             diverted: action?.requiresDivert ?? false,
                                             rawXY: isGesture(action))
        }
    }

    func reconnect() {
        stop()
        isConnected = false
        onStatus?("Reconnecting…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            _ = self?.start()
        }
    }

    func stop() {
        stopped = true
        pingTimer?.cancel()
        pingTimer = nil
        watchdog = nil
        restoreNativeDiverts()
        gestureDetector.end()
        gestureCID = nil
        scrollWheelTap?.stop()
        loopThread = nil
        monitor = nil
        session = nil
    }

    private func applyDiverts(controlsService: ReprogrammableControls) {
        let config = currentConfig()
        for control in controls where control.isDivertable {
            let action = config.action(forCID: control.cid)
            let shouldDivert = (action != nil) && (action != .disabled)
            Self.log.info("applyDiverts cid=0x\(String(format: "%04X", control.cid), privacy: .public) divert=\(shouldDivert ? 1 : 0) rawXY=\(self.isGesture(action) ? 1 : 0) action=\(String(describing: action), privacy: .public)")
            try? controlsService.setDiverted(cid: control.cid,
                                             diverted: shouldDivert,
                                             rawXY: isGesture(action))
        }
    }

    private func isGesture(_ action: ButtonAction?) -> Bool {
        if case .gesture? = action { return true }
        return false
    }

    private func refreshConfig() {
        let config = configStore.load()
        configLock.lock()
        cachedConfig = config
        configLock.unlock()
    }

    private func currentConfig() -> Config {
        configLock.lock()
        defer { configLock.unlock() }
        return cachedConfig
    }

    private func restoreNativeDiverts() {
        guard let controlsService else { return }
        for control in controls where control.isDivertable {
            try? controlsService.setDiverted(cid: control.cid, diverted: false)
        }
        try? controlsService.resetRemap(cid: 0x0050)
        try? controlsService.resetRemap(cid: 0x0051)
    }

    private func applySwapIfNeeded(controlsService: ReprogrammableControls) {
        guard controls.contains(where: { $0.cid == 0x0050 }),
              controls.contains(where: { $0.cid == 0x0051 }) else { return }
        let swapped = currentConfig().swapLeftRight
        Self.log.info("swap left/right: \(swapped ? "on" : "off")")
        try? controlsService.setRemapped(cid: 0x0050, target: swapped ? 0x0051 : 0x0000)
        try? controlsService.setRemapped(cid: 0x0051, target: swapped ? 0x0050 : 0x0000)
    }

    private func applySmartShiftIfNeeded(service: SmartShiftControls) {
        let config = currentConfig()
        guard let mode = config.smartShiftMode else { return }
        let status = SmartShiftStatus.status(for: mode,
                                             sensitivity: config.smartShiftSensitivity ?? 16)
        Self.log.info("smartshift mode: \(mode.rawValue) sens: \(status.autoDisengage)")
        try? service.setRatchetControlMode(status: status)
    }

    private func applyDPIIfNeeded(service: AdjustableDPI) {
        guard let dpi = currentConfig().dpiValue else { return }
        Self.log.info("dpi: \(dpi)")
        try? service.setSensorDpi(sensor: 0, dpi: dpi)
    }

    private func cycleDPI() {
        guard let service = _dpiService else { return }
        ioQueue.async { [weak self] in
            guard let self, !self.stopped else { return }
            let config = self.currentConfig()
            let current = config.dpiValue ?? (try? service.getSensorDpi(sensor: 0))?.dpi ?? 0
            let presets = config.dpiCycleValues ?? DPICycle.defaultPresets
            guard let next = DPICycle.next(current: current, presets: presets) else { return }
            var newConfig = config
            newConfig.dpiValue = next
            try? self.configStore.save(newConfig)
            self.refreshConfig()
            try? service.setSensorDpi(sensor: 0, dpi: next)
            Self.log.info("dpi cycle: \(current) -> \(next)")
        }
    }

    private func applyScrollInversionIfNeeded(service: HiResWheel) {
        guard let invert = currentConfig().invertScrollDirection else { return }
        Self.log.info("scroll invert: \(invert)")
        try? service.setInverted(invert)
    }

    private func setupWatchdog() {
        let watchdog = ConnectionWatchdog(failureThreshold: 3)
        watchdog.onDisconnected = { [weak self] in
            guard let self else { return }
            Self.log.info("device lost (3 failed pings)")
            EngineEvents.shared.onDisconnected?()
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = false
                self?.onStatus?("Disconnected")
            }
        }
        watchdog.onReconnected = { [weak self] in
            guard let self else { return }
            Self.log.info("device back (ping answered)")
            EngineEvents.shared.onConnected?()
            self.ioQueue.async { [weak self] in
                guard let self, let controlsService = self.controlsService, !self.stopped else { return }
                self.applyAll(controlsService: controlsService)
            }
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = true
                self?.onStatus?("Connected — \(self?.controls.count ?? 0) controls")
            }
        }
        self.watchdog = watchdog

        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + Self.pingInterval,
                       repeating: Self.pingInterval,
                       leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self, let session = self.session, !self.stopped else { return }
            let answered = (try? session.ping(deviceIndex: self.deviceIndex)) ?? false
            self.watchdog?.report(ok: answered)
        }
        timer.resume()
        pingTimer = timer
    }

    private func startLoopThread(monitor: DivertedButtonMonitor) {
        let thread = Thread { [weak self] in
            guard let self else { return }
            while !self.stopped {
                guard let session = self.session else { break }
                if let report = try? session.readReport(timeout: 0.05) {
                    _ = monitor.feed(report)
                }
            }
        }
        thread.name = "RatTamer.ButtonLoop"
        thread.start()
        loopThread = thread
    }

    private func handlePress(_ cid: UInt16) {
        guard enabled else {
            Self.log.info("press cid=0x\(String(format: "%04X", cid), privacy: .public) ignored (disabled)")
            return
        }
        let config = currentConfig()
        guard let action = config.action(forCID: cid), action != .disabled else {
            Self.log.info("press cid=0x\(String(format: "%04X", cid), privacy: .public) ignored (no action)")
            return
        }
        Self.log.info("press cid=0x\(String(format: "%04X", cid), privacy: .public) action=\(String(describing: action), privacy: .public)")
        if case .gesture(let gestureConfig) = action {
            gestureDetector.begin(config: gestureConfig)
            gestureCID = cid
            return
        }
        if action == .cycleDPI {
            onButtonEvent?(cid)
            cycleDPI()
            return
        }
        onButtonEvent?(cid)
        do {
            try actionEngine.execute(action)
        } catch {
            Self.log.error("execute failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func handleRelease(_ cid: UInt16) {
        if gestureCID == cid {
            gestureCID = nil
            gestureDetector.end()
        }
        onButtonReleased?(cid)
    }

    private func handleRawXY(dx: Int16, dy: Int16) {
        gestureDetector.motion(dx: dx, dy: dy)
    }

    private func thumbWheelConfigAction(_ direction: ThumbWheel.Direction) -> ButtonAction? {
        let config = currentConfig()
        switch direction {
        case .left: return config.thumbWheelLeft
        case .right: return config.thumbWheelRight
        }
    }

    private func hasThumbWheelAction(_ direction: ThumbWheel.Direction) -> Bool {
        let action = thumbWheelConfigAction(direction)
        return action != nil && action != .disabled
    }

    private func executeThumbWheelNotch(_ direction: ThumbWheel.Direction) {
        guard let action = thumbWheelConfigAction(direction), action != .disabled else { return }
        ioQueue.async { [weak self] in
            guard let self, !self.stopped else { return }
            do {
                try self.actionEngine.execute(action)
            } catch {
                Self.log.error("thumb wheel execute failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
