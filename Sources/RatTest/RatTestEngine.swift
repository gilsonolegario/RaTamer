import ApplicationServices
import CoreGraphics
import Foundation
import RatTamerCore

final class RatTestEngine {
    let configStore: ConfigStore
    private let actionEngine = ActionEngine(poster: CGEventPoster())
    private var session: HIDPPSession?
    private var controlsService: ReprogrammableControls?
    private var monitor: DivertedButtonMonitor?
    private var loopThread: Thread?
    private let deviceIndex: UInt8 = 1
    private var stopped = false

    var onStatus: ((String) -> Void)?
    var onControlsChanged: (([ControlInfo]) -> Void)?
    var onPress: ((UInt16) -> Void)?
    var onRelease: ((UInt16) -> Void)?
    private(set) var controls: [ControlInfo] = []
    private var hiResWheelService: HiResWheel?
    private var smoothCoordinator: ScrollSmootherCoordinator?
    private(set) var wheelMultiplier: UInt8?

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    func start() -> Bool {
        stopped = false
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
            onControlsChanged?(controls)

            var wheelFeatureIndex: UInt8?
            if let wheelIndex = try? session.getFeatureIndex(
                featureID: HiResWheel.featureID, deviceIndex: deviceIndex
            ) {
                wheelFeatureIndex = wheelIndex
                let service = HiResWheel(session: session,
                                         deviceIndex: deviceIndex,
                                         featureIndex: wheelIndex)
                self.hiResWheelService = service
                self.wheelMultiplier = (try? service.getInfo())?.multiplier
            }

            let monitor = DivertedButtonMonitor(deviceIndex: deviceIndex,
                                                featureIndex: featureIndex,
                                                wheelFeatureIndex: wheelFeatureIndex)
            monitor.onControlPressed = { [weak self] cid in self?.onPress?(cid) }
            monitor.onControlReleased = { [weak self] cid in self?.onRelease?(cid) }
            monitor.onWheelMovement = { [weak self] movement in
                self?.smoothCoordinator?.onWheelMovement(movement)
            }
            self.monitor = monitor

            for control in controls where control.isDivertable {
                try? controlsService.setDiverted(cid: control.cid, diverted: true)
            }
            startLoopThread(monitor: monitor)
            onStatus?("Connected — \(controls.count) controls")
            return true
        } catch {
            onStatus?("Not connected: \(error)")
            return false
        }
    }

    func stop() {
        stopped = true
        if let controlsService {
            for control in controls where control.isDivertable {
                try? controlsService.setDiverted(cid: control.cid, diverted: false)
            }
        }
        loopThread = nil
        monitor = nil
        smoothCoordinator?.stop()
        smoothCoordinator = nil
        if let service = hiResWheelService {
            try? service.setWheelMode(highResolution: false, target: false)
        }
        session = nil
        controlsService = nil
    }

    func runAction(for cid: UInt16) {
        let config = configStore.load()
        guard let action = config.action(forCID: cid), action != .disabled else { return }
        try? actionEngine.execute(action)
    }

    func saveAction(_ action: ButtonAction, for cid: UInt16) {
        var config = configStore.load()
        config.setAction(action, forCID: cid)
        try? configStore.save(config)
    }

    func setSmoothScroll(enabled: Bool, parameters: ScrollSmoother.Parameters) {
        guard let service = hiResWheelService else { return }
        try? service.setWheelMode(highResolution: enabled, target: enabled)
        smoothCoordinator?.stop()
        smoothCoordinator = nil
        guard enabled else { return }
        let coordinator = ScrollSmootherCoordinator(
            smoother: ScrollSmoother(parameters: parameters)
        ) { [weak self] pixels in
            self?.postPixels(pixels)
        }
        coordinator.start()
        smoothCoordinator = coordinator
    }

    func setSmoothParameters(_ parameters: ScrollSmoother.Parameters) {
        smoothCoordinator?.setParameters(parameters)
    }

    private func postPixels(_ pixels: Double) {
        guard AXIsProcessTrusted() else { return }
        let value = Int32(pixels.rounded())
        guard value != 0 else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 1, wheel1: value, wheel2: 0, wheel3: 0) else {
            return
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
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
        thread.name = "RatTest.ButtonLoop"
        thread.start()
        loopThread = thread
    }
}
