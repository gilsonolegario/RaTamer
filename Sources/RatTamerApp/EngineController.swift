import AppKit
import ApplicationServices
import Foundation
import RatTamerCore
import os

final class EngineController {
    enum ConnectionState {
        case connected
        case disconnected
        case reconnecting
    }

    private static let log = Logger(subsystem: "com.rattamer", category: "engine")
    private let configStore: ConfigStore
    private var session: HIDPPSession?
    private var controlsService: ReprogrammableControls?
    private var monitor: DivertedButtonMonitor?
    private var loopThread: Thread?
    private var loopExitSignal: DispatchSemaphore?
    private let deviceIndex: UInt8 = 1
    private let actionEngine: ActionEngine
    private let gestureDetector: GestureDetector
    private var gestureCID: UInt16?
    private var scrollWheelTap: ScrollWheelTap?
    private var smartShiftService: SmartShiftControls?
    private var _dpiService: AdjustableDPI?
    private var _batteryService: BatteryStatus?
    private var _hiResWheelService: HiResWheel?
    private var smoothCoordinator: ScrollSmootherCoordinator?
    /// Where live scroll samples (raw + output) are forwarded while the
    /// scroll graph is visible. Wired by ScrollGraphView on appear/disappear.
    var scrollSampleSink: ((ScrollSample) -> Void)?
    private var stopped = false
    private var _enabled = true
    private let enabledLock = NSLock()
    private var cachedConfig: Config
    private let configLock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.rattamer.io")
    private var watchdog: ConnectionWatchdog?
    private var pingTimer: DispatchSourceTimer?
    private var frontmostObserver: NSObjectProtocol?
    private static let pingInterval: TimeInterval = 2.0
    private let actionThrottle = ActionThrottle(minInterval: 0.25, holdTimeout: 10)
    private static let throttleLog = RateLimitedLogger(interval: 5.0)
    private static let retryBaseDelay: TimeInterval = 2.0
    private static let retryMaxDelay: TimeInterval = 30.0
    /// Delay of a wake-driven recovery attempt: the receiver is usually
    /// re-enumerated right after wake, so probing almost immediately avoids
    /// waiting out the full backoff.
    private static let wakeRecoveryDelay: TimeInterval = 0.15
    private var retryAttempt = 0
    private var retryGeneration = 0
    /// Automatic recovery loop started when the watchdog declares the device
    /// lost. `recoveryGeneration` is bumped to supersede/cancel any pending
    /// loop (single-flight); all mutations happen on the main queue.
    private var recoveryGeneration = 0
    private var recoveryAttempt = 0
    private var wakeObserver: NSObjectProtocol?

    private func logThrottled(_ message: String) {
        guard Self.throttleLog.shouldLog() else { return }
        Self.log.error("\(message, privacy: .public)")
    }

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
                    self.restoreSmoothScroll()
                }
            }
        }
    }

    var onStatus: ((_ text: String) -> Void)?
    var onConnectionState: ((ConnectionState) -> Void)?
    var onButtonEvent: ((_ cid: UInt16) -> Void)?
    var onButtonReleased: ((_ cid: UInt16) -> Void)?
    var onControlsChanged: (([ControlInfo]) -> Void)?
    private(set) var isConnected = false
    private(set) var controls: [ControlInfo] = []
    private(set) var deviceName = "HID++ device"
    private(set) var capabilities = DeviceCapabilities(hasReprogrammableControls: false,
                                                       hasBattery: false,
                                                       hasDPI: false,
                                                       hasSmartShift: false)
    var dpiService: AdjustableDPI? { _dpiService }
    var batteryStatusService: BatteryStatus? { _batteryService }
    var hiResWheelService: HiResWheel? { _hiResWheelService }

    init(configStore: ConfigStore) {
        self.configStore = configStore
        let poster = CGEventPoster()
        poster.isFrontmostTerminal = { FrontmostAppGuard.isFrontmostTerminal() }
        self.actionEngine = ActionEngine(poster: poster)
        self.actionEngine.isFrontmostTerminal = { FrontmostAppGuard.isFrontmostTerminal() }
        self.cachedConfig = configStore.load()
        self.gestureDetector = GestureDetector(actionEngine: actionEngine)
        let tap = ScrollWheelTap(
            shouldIntercept: { [weak self] direction in
                guard let self, self.enabled, self.isConnected else { return false }
                guard !FrontmostAppGuard.isFrontmostTerminal() else { return false }
                return self.hasThumbWheelAction(direction)
            },
            onNotch: { [weak self] direction in
                self?.executeThumbWheelNotch(direction)
            }
        )
        self.scrollWheelTap = tap
    }

    func start() -> Bool {
        // Any real start (manual, scheduleRetry or recovery restart)
        // supersedes any pending automatic recovery attempt.
        cancelRecovery()
        stopped = false
        ActionEngine.warmKeyCodeCache()
        // All callers reach start() with session == nil (fresh controller,
        // previous start failure already closed it in the catch below, or a
        // stop()/reconnect() ran first), so there is no live session leak.
        do {
            let device = try HIDLocator.openReceiver()
            let session = HIDPPSession(device: device)
            self.session = session
            self.deviceName = (try? session.readProductName(deviceIndex: deviceIndex)) ?? "HID++ device"
            guard let featureIndex = try session.getFeatureIndex(
                featureID: ReprogrammableControls.featureID, deviceIndex: deviceIndex
            ) else {
                onStatus?("0x1B04 feature not found")
                session.close()
                self.session = nil
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
                featureID: SmartShiftControls.enhancedFeatureID, deviceIndex: deviceIndex
            ) {
                self.smartShiftService = SmartShiftControls(session: session,
                                                            deviceIndex: deviceIndex,
                                                            featureIndex: smartShiftIndex,
                                                            featureID: SmartShiftControls.enhancedFeatureID)
            } else if let smartShiftIndex = try? session.getFeatureIndex(
                featureID: SmartShiftControls.featureID, deviceIndex: deviceIndex
            ) {
                self.smartShiftService = SmartShiftControls(session: session,
                                                            deviceIndex: deviceIndex,
                                                            featureIndex: smartShiftIndex)
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
            } else if let batteryIndex = try? session.getFeatureIndex(
                featureID: BatteryStatus.unifiedFeatureID, deviceIndex: deviceIndex
            ) {
                self._batteryService = BatteryStatus(session: session,
                                                     deviceIndex: deviceIndex,
                                                     featureIndex: batteryIndex,
                                                     featureID: BatteryStatus.unifiedFeatureID)
            }
            var wheelFeatureIndex: UInt8?
            if let wheelIndex = try? session.getFeatureIndex(
                featureID: HiResWheel.featureID, deviceIndex: deviceIndex
            ) {
                wheelFeatureIndex = wheelIndex
                self._hiResWheelService = HiResWheel(session: session,
                                                     deviceIndex: deviceIndex,
                                                     featureIndex: wheelIndex)
            }

            let hasSmartShift = _hiResWheelService.map { ((try? $0.getInfo())?.hasSwitch ?? false) } ?? false
            self.capabilities = DeviceCapabilities(hasReprogrammableControls: true,
                                                   hasBattery: _batteryService != nil,
                                                   hasDPI: _dpiService != nil,
                                                   hasSmartShift: hasSmartShift)

            let monitor = DivertedButtonMonitor(deviceIndex: deviceIndex,
                                                featureIndex: featureIndex,
                                                wheelFeatureIndex: wheelFeatureIndex)
            monitor.onControlPressed = { [weak self] cid in
                self?.handlePress(cid)
            }
            monitor.onControlReleased = { [weak self] cid in
                self?.handleRelease(cid)
            }
            monitor.onRawXY = { [weak self] dx, dy in
                self?.handleRawXY(dx: dx, dy: dy)
            }
            monitor.onWheelMovement = { [weak self] movement in
                self?.handleWheelMovement(movement)
            }
            self.monitor = monitor

            refreshConfig()
            applyAll(controlsService: controlsService)
            setupWatchdog()
            startLoopThread(monitor: monitor)
            startFrontmostObserver()
            startWakeObserver()
            isConnected = true
            retryAttempt = 0
            EngineEvents.shared.onConnected?()
            onConnectionState?(.connected)
            if AXIsProcessTrusted() {
                scrollWheelTap?.start()
                onStatus?("Connected — \(controls.count) controls")
            } else {
                onStatus?("Connected — conceda Acessibilidade para atalhos/gestos")
            }
            return true
        } catch {
            isConnected = false
            session?.close()
            session = nil
            onConnectionState?(.disconnected)
            onStatus?("Not connected: \(error)")
            scheduleRetry()
            return false
        }
    }

    /// Retries connecting with exponential backoff while the receiver is
    /// unavailable (e.g. not ready yet at login). Stops as soon as a connect
    /// succeeds or the engine is stopped.
    private func scheduleRetry() {
        guard !stopped else { return }
        let generation = retryGeneration
        let delay = RetryPolicy.delay(attempt: retryAttempt,
                                      base: Self.retryBaseDelay,
                                      maxDelay: Self.retryMaxDelay)
        retryAttempt += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped, self.retryGeneration == generation else { return }
            Self.log.notice("retrying connection (attempt \(self.retryAttempt))")
            _ = self.start()
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
        guard !stopped else { return }
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
        if let service = _hiResWheelService {
            applySmoothScrollIfNeeded(service: service)
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

    /// Automatic recovery after the watchdog declares the device lost (e.g.
    /// the receiver was re-enumerated by the system and the old IOKit handle
    /// is dead). After a grace period it tries to reopen the device from
    /// scratch and restart the whole engine; failures retry with exponential
    /// backoff indefinitely until the device answers or the engine stops.
    /// Single-flight: at most one loop is pending; `reconnect()` supersedes it.
    private func beginRecovery(immediate: Bool = false) {
        recoveryGeneration += 1
        let generation = recoveryGeneration
        recoveryAttempt = 0
        scheduleRecoveryAttempt(generation: generation, immediate: immediate)
    }

    private func scheduleRecoveryAttempt(generation: Int, immediate: Bool) {
        // First attempt lands after ~one extra ping interval of grace so an
        // RF hiccup that the watchdog can still reverse does not race a
        // reopen; later attempts use the exponential backoff.
        let delay = immediate
            ? Self.wakeRecoveryDelay
            : RetryPolicy.delay(attempt: recoveryAttempt,
                                base: Self.retryBaseDelay,
                                maxDelay: Self.retryMaxDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped, self.recoveryGeneration == generation else { return }
            Self.log.notice("recovery: reopening receiver (attempt \(self.recoveryAttempt + 1))")
            // HID++ replies arrive as input reports delivered to every open
            // client, so the stale engine session may swallow the probe's
            // reply and cause a spurious failure. Accepted: it only costs one
            // backoff cycle and the loop self-heals.
            do {
                let device = try HIDLocator.openReceiver()
                let probe = HIDPPSession(device: device)
                defer { probe.close() }
                guard try probe.ping(deviceIndex: self.deviceIndex) else {
                    Self.log.notice("recovery: probe ping unanswered")
                    self.recoveryAttempt += 1
                    self.scheduleRecoveryAttempt(generation: generation, immediate: false)
                    return
                }
            } catch {
                Self.log.notice("recovery: reopen failed (\(error, privacy: .public))")
                self.recoveryAttempt += 1
                self.scheduleRecoveryAttempt(generation: generation, immediate: false)
                return
            }
            Self.log.notice("recovery: device answering — restarting engine")
            self.restartEngine()
        }
    }

    /// Cancels any pending automatic recovery loop by superseding its
    /// generation. Called from start(), stop()/reconnect().
    private func cancelRecovery() {
        recoveryGeneration += 1
        recoveryAttempt = 0
    }

    /// Restarts the engine on a fresh device handle once the probe confirms
    /// the receiver answers again. The stop() inside supersedes this recovery
    /// loop and any pending scheduleRetry attempt.
    private func restartEngine() {
        stop()
        scheduleEngineRestart()
    }

    /// Shared tail of manual reconnect and automatic recovery: tears down
    /// (caller runs stop()), then boots a fresh engine after a short settle.
    private func scheduleEngineRestart() {
        isConnected = false
        onConnectionState?(.reconnecting)
        onStatus?("Reconnecting…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            _ = self?.start()
        }
    }

    func reconnect() {
        // A manual reconnect supersedes any pending automatic recovery loop.
        cancelRecovery()
        stop()
        scheduleEngineRestart()
    }

    func stop() {
        stopped = true
        retryGeneration += 1
        cancelRecovery()
        pingTimer?.cancel()
        pingTimer = nil
        watchdog = nil
        stopFrontmostObserver()
        stopWakeObserver()
        restoreNativeDiverts()
        restoreSmoothScroll()
        gestureDetector.end()
        gestureCID = nil
        scrollWheelTap?.stop()
        session?.wake()
        loopExitSignal?.wait()
        loopExitSignal = nil
        loopThread = nil
        monitor = nil
        session?.close()
        session = nil
    }

    private func applyDiverts(controlsService: ReprogrammableControls) {
        let config = currentConfig()
        for control in controls where control.isDivertable {
            let action = config.action(forCID: control.cid)
            let shouldDivert = (action != nil) && (action != .disabled)
            Self.log.info("applyDiverts cid=0x\(String(format: "%04X", control.cid), privacy: .public) divert=\(shouldDivert ? 1 : 0) rawXY=\(self.isGesture(action) ? 1 : 0) action=\(String(describing: action), privacy: .public)")
            do {
                try controlsService.setDiverted(cid: control.cid,
                                                diverted: shouldDivert,
                                                rawXY: isGesture(action))
            } catch {
                Self.log.error("setDiverted failed: \(error)")
            }
        }
    }

    private func isGesture(_ action: ButtonAction?) -> Bool {
        if case .gesture? = action { return true }
        return false
    }

    private func refreshConfig() {
        let config = configStore.load()
        FrontmostAppGuard.isEnabled = config.protectTerminals ?? true
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
            do {
                try controlsService.setDiverted(cid: control.cid, diverted: false)
            } catch {
                Self.log.error("setDiverted failed: \(error)")
            }
        }
        do {
            try controlsService.resetRemap(cid: ControlCID.leftButton)
        } catch {
            Self.log.error("resetRemap failed: \(error)")
        }
        do {
            try controlsService.resetRemap(cid: ControlCID.rightButton)
        } catch {
            Self.log.error("resetRemap failed: \(error)")
        }
    }

    private func applySwapIfNeeded(controlsService: ReprogrammableControls) {
        guard controls.contains(where: { $0.cid == ControlCID.leftButton }),
              controls.contains(where: { $0.cid == ControlCID.rightButton }) else { return }
        let swapped = currentConfig().swapLeftRight
        Self.log.info("swap left/right: \(swapped ? "on" : "off")")
        do {
            try controlsService.setRemapped(cid: ControlCID.leftButton, target: swapped ? ControlCID.rightButton : 0x0000)
        } catch {
            Self.log.error("setRemapped failed: \(error)")
        }
        do {
            try controlsService.setRemapped(cid: ControlCID.rightButton, target: swapped ? ControlCID.leftButton : 0x0000)
        } catch {
            Self.log.error("setRemapped failed: \(error)")
        }
    }

    private func applySmartShiftIfNeeded(service: SmartShiftControls) {
        let config = currentConfig()
        guard let mode = config.smartShiftMode else { return }
        let status = SmartShiftStatus.status(for: mode,
                                             sensitivity: config.smartShiftSensitivity ?? 16)
        Self.log.info("smartshift mode: \(mode.rawValue) sens: \(status.autoDisengage)")
        do {
            try service.setRatchetControlMode(status: status)
        } catch {
            Self.log.error("setRatchetControlMode failed: \(error)")
        }
    }

    private func applyDPIIfNeeded(service: AdjustableDPI) {
        guard let dpi = currentConfig().dpiValue else { return }
        Self.log.info("dpi: \(dpi)")
        do {
            try service.setSensorDpi(sensor: 0, dpi: dpi)
        } catch {
            Self.log.error("setSensorDpi failed: \(error)")
        }
    }

    private func cycleDPI() {
        guard let service = _dpiService else { return }
        ioQueue.async { [weak self] in
            guard let self, !self.stopped else { return }
            let config = self.currentConfig()
            let current = config.dpiValue ?? (try? service.getSensorDpi(sensor: 0))?.dpi ?? 0
            let sensorList = (try? service.getSensorDpiList(sensor: 0)) ?? []
            let presets = config.dpiCycleValues ?? DPICycle.recommendedPresets(from: sensorList)
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
        Self.log.notice("scroll invert: \(invert)")
        do {
            try service.setInverted(invert)
        } catch {
            Self.log.error("setInverted failed: \(error)")
        }
    }

    private func applySmoothScrollIfNeeded(service: HiResWheel) {
        let config = currentConfig()
        let enabled = config.smoothScrollEnabled == true
        guard !enabled || !FrontmostAppGuard.isFrontmostTerminal() else {
            Self.log.info("smooth scroll: skipped — terminal frontmost")
            return
        }
        Self.log.info("smooth scroll: \(enabled ? "on" : "off")")
        do {
            try service.setWheelMode(highResolution: enabled, target: enabled)
        } catch {
            Self.log.error("setWheelMode failed: \(error)")
        }
        smoothCoordinator?.stop()
        smoothCoordinator = nil
        guard enabled else { return }
        let info = try? service.getInfo()
        let settings = SmoothScrollSettings(level: config.smoothScrollLevel,
                                            advanced: config.smoothScrollAdvanced,
                                            multiplier: info?.multiplier ?? 8,
                                            invert: softwareScrollInvert())
        let coordinator = ScrollSmootherCoordinator(smoother: ScrollSmoother(parameters: settings.parameters)) { [weak self] pixels in
            self?.postSmoothScroll(pixels)
        }
        coordinator.onSample = { [weak self] sample in
            self?.scrollSampleSink?(sample)
        }
        coordinator.start()
        smoothCoordinator = coordinator
    }

    /// Applies a new parameter set live without rebuilding the coordinator,
    /// so slider tweaks take effect without stopping in-flight momentum.
    /// `multiplier` and `invert` are always re-derived here, never trusted
    /// from the caller.
    func updateSmoothParameters(_ parameters: ScrollSmoother.Parameters) {
        guard let service = _hiResWheelService else { return }
        var params = parameters
        params.multiplier = (try? service.getInfo())?.multiplier ?? 8
        params.invert = softwareScrollInvert()
        smoothCoordinator?.setParameters(params)
    }

    /// Software-side inversion for the smooth-scroll (diverted) path. The
    /// HiResWheel invert bit flips only values reported natively via HID; in
    /// diverted mode the HID++ wheel notifications are never inverted by the
    /// hardware, so software must apply the configured direction as-is.
    private func softwareScrollInvert() -> Bool {
        currentConfig().invertScrollDirection ?? false
    }

    private func restoreSmoothScroll() {
        smoothCoordinator?.stop()
        smoothCoordinator = nil
        guard let service = _hiResWheelService else { return }
        do {
            try service.setWheelMode(highResolution: false, target: false)
        } catch {
            Self.log.error("setWheelMode failed: \(error)")
        }
    }

    private func handleWheelMovement(_ movement: WheelMovement) {
        guard enabled else { return }
        guard let coordinator = smoothCoordinator else { return }
        coordinator.onWheelMovement(movement)
    }

    private func postSmoothScroll(_ pixels: Double) {
        guard Permissions.isAccessibilityTrusted() else { return }
        guard !FrontmostAppGuard.isFrontmostTerminal() else { return }
        let value = Int32(pixels.rounded())
        guard value != 0 else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 1, wheel1: value, wheel2: 0, wheel3: 0) else {
            return
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
    }

    /// Tracks the frontmost app so a terminal in focus can restore the native
    /// wheel mode (hi-res diverts HID wheel events, so blocking the smooth post
    /// alone would leave the wheel dead in the terminal).
    private func startFrontmostObserver() {
        guard frontmostObserver == nil else { return }
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleFrontmostAppChanged()
        }
    }

    private func stopFrontmostObserver() {
        if let observer = frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            frontmostObserver = nil
        }
    }

    /// Waking from sleep often re-enumerates the receiver and kills the old
    /// IOKit handle. If the engine is (or goes) disconnected, skip any pending
    /// recovery backoff and try to reopen immediately.
    private func startWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard !self.isConnected else { return }
            Self.log.notice("wake: disconnected — recovering immediately")
            self.beginRecovery(immediate: true)
        }
    }

    private func stopWakeObserver() {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    private func handleFrontmostAppChanged() {
        let isTerminal = FrontmostAppGuard.isFrontmostTerminal()
        ioQueue.async { [weak self] in
            guard let self, let service = self._hiResWheelService, !self.stopped else { return }
            if isTerminal {
                Self.log.info("terminal frontmost — restoring native wheel")
                self.restoreSmoothScroll()
            } else if self.enabled {
                Self.log.info("terminal left — reapplying smooth scroll")
                self.applySmoothScrollIfNeeded(service: service)
            }
        }
    }

    private func setupWatchdog() {
        let watchdog = ConnectionWatchdog(failureThreshold: 3)
        watchdog.onDisconnected = { [weak self] in
            guard let self else { return }
            Self.log.notice("device lost (3 failed pings)")
            EngineEvents.shared.onDisconnected?()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isConnected = false
                self.onConnectionState?(.disconnected)
                self.onStatus?("Disconnected")
                // The IOKit handle may be dead (receiver re-enumerated,
                // sleep/wake): start the automatic reopen-restart loop. If
                // the old handle revives first, onReconnected cancels it.
                self.beginRecovery()
            }
        }
        watchdog.onReconnected = { [weak self] in
            guard let self else { return }
            Self.log.notice("device back (ping answered)")
            EngineEvents.shared.onConnected?()
            DispatchQueue.main.async { [weak self] in
                // Same handle recovered (RF hiccup): drop any pending
                // automatic recovery loop and just reapply the config.
                self?.cancelRecovery()
            }
            self.ioQueue.async { [weak self] in
                guard let self, let controlsService = self.controlsService, !self.stopped else { return }
                self.applyAll(controlsService: controlsService)
            }
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = true
                self?.onConnectionState?(.connected)
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
        let exitSignal = DispatchSemaphore(value: 0)
        loopExitSignal = exitSignal
        let thread = Thread { [weak self] in
            defer { exitSignal.signal() }
            guard let self else { return }
            guard let session = self.session else { return }
            while !self.stopped {
                if var report = try? session.readReport(timeout: .greatestFiniteMagnitude) {
                    _ = monitor.feed(report)
                    session.recycle(&report)
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
        let stateKey = "press-state-\(cid)"
        guard actionThrottle.acquire(stateKey) else {
            logThrottled("press cid=0x\(String(format: "%04X", cid)) repeated while already pressed — ignored")
            return
        }
        guard actionThrottle.shouldFire("press-\(cid)") else {
            logThrottled("press cid=0x\(String(format: "%04X", cid)) throttled — ignored")
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
        actionThrottle.release("press-state-\(cid)")
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
            let key = direction == .left ? "wheel-left" : "wheel-right"
            guard self.actionThrottle.shouldFire(key) else { return }
            do {
                try self.actionEngine.execute(action)
            } catch {
                Self.log.error("thumb wheel execute failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
