import Foundation

public enum BatteryLevel: String, Equatable {
    case critical, low, good, full, unknown

    public static func fromCapacity(_ capacity: UInt8) -> BatteryLevel {
        if capacity < 11 {
            return .critical
        } else if capacity < 30 {
            return .low
        } else if capacity < 81 {
            return .good
        }
        return .full
    }
}

public enum BatteryState: String, Equatable {
    case discharging, recharging, charging, full, notCharging, unknown

    public static func fromRaw(_ raw: UInt8) -> BatteryState {
        switch raw {
        case 0: return .discharging
        case 1: return .recharging
        case 2, 4: return .charging
        case 3: return .full
        case 5, 6, 7: return .notCharging
        default: return .unknown
        }
    }
}

public struct BatteryInfo: Equatable {
    public let capacity: UInt8
    public let nextCapacity: UInt8
    public let state: BatteryState
    public let level: BatteryLevel

    public init(capacity: UInt8, nextCapacity: UInt8, state: BatteryState, level: BatteryLevel) {
        self.capacity = capacity
        self.nextCapacity = nextCapacity
        self.state = state
        self.level = level
    }
}

public final class BatteryStatus {
    public static let featureID: UInt16 = 0x1000
    public static let unifiedFeatureID: UInt16 = 0x1004

    private let session: HIDPPSession
    private let deviceIndex: UInt8
    private let featureIndex: UInt8
    public let featureID: UInt16

    public init(session: HIDPPSession, deviceIndex: UInt8, featureIndex: UInt8,
                featureID: UInt16 = BatteryStatus.featureID) {
        self.session = session
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
        self.featureID = featureID
    }

    public func getBatteryInfo() throws -> BatteryInfo {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x00),
              resp.count >= 7 else {
            throw NSError(domain: "BatteryStatus", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "short response"])
        }
        let capacity = resp[4]
        let nextCapacityIndex = featureID == Self.unifiedFeatureID ? 6 : 5
        let nextCapacity = resp[nextCapacityIndex]
        let stateIndex = featureID == Self.unifiedFeatureID ? 5 : 6
        let rawState = resp[stateIndex]
        let state = BatteryState.fromRaw(rawState)
        let level: BatteryLevel
        if state == .full {
            level = .full
        } else if capacity > 0 {
            level = BatteryLevel.fromCapacity(capacity)
        } else {
            level = .unknown
        }
        return BatteryInfo(capacity: state == .full ? 100 : capacity,
                           nextCapacity: nextCapacity,
                           state: state,
                           level: level)
    }
}
