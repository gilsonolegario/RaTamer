import AppKit
import Combine
import RaTamerCore

final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published var info: BatteryInfo?

    private var timer: Timer?
    private static let interval: TimeInterval = 60

    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh()
        // `scheduledTimer` only fires in the default run-loop mode, so it
        // stalls while the user is dragging a slider or scrolling (event
        // tracking). Register in the common modes so the poll keeps running.
        let poll = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        // `refresh` is always called on the main thread (Timer on main run loop),
        // so capturing the service here before hopping to background is safe.
        let service = AppModel.shared.engine?.batteryStatusService
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let service else {
                DispatchQueue.main.async { self?.info = nil }
                return
            }
            if let info = try? service.getBatteryInfo() {
                DispatchQueue.main.async { self?.info = info }
            }
        }
    }
}

enum BatteryDisplay {
    static func title(for info: BatteryInfo) -> String {
        switch info.state {
        case .full:
            return "Battery: Full"
        case .recharging, .charging:
            return "Battery: Charging"
        case .notCharging:
            return "Battery: Not charging"
        case .discharging:
            return "Battery: \(info.level.rawValue.capitalized) (\(info.capacity)%)"
        case .unknown:
            return "Battery: \(info.level.rawValue.capitalized)"
        }
    }

    static func symbol(for info: BatteryInfo) -> String {
        if info.state == .charging || info.state == .recharging {
            return "bolt.fill"
        }
        switch info.capacity {
        case 80...255: return "battery.100percent"
        case 60...79: return "battery.75percent"
        case 40...59: return "battery.50percent"
        case 20...39: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}
