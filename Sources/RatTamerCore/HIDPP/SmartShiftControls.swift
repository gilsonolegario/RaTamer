import Foundation

public struct SmartShiftStatus: Codable, Equatable {
    public var wheelMode: UInt8
    public var autoDisengage: UInt8
    public var autoDisengageDefault: UInt8

    public init(wheelMode: UInt8, autoDisengage: UInt8, autoDisengageDefault: UInt8) {
        self.wheelMode = wheelMode
        self.autoDisengage = autoDisengage
        self.autoDisengageDefault = autoDisengageDefault
    }

    public static func status(for mode: SmartShiftMode, sensitivity: Int) -> SmartShiftStatus {
        switch mode {
        case .freespin:
            return SmartShiftStatus(wheelMode: 1, autoDisengage: 0x00, autoDisengageDefault: 0)
        case .ratcheted:
            return SmartShiftStatus(wheelMode: 2, autoDisengage: 0xFF, autoDisengageDefault: 0)
        case .smartshift:
            let clamped = UInt8(min(max(sensitivity, 1), 254))
            return SmartShiftStatus(wheelMode: 2, autoDisengage: clamped, autoDisengageDefault: 0)
        }
    }
}

public final class SmartShiftControls {
    public static let featureID: UInt16 = 0x2110
    public static let enhancedFeatureID: UInt16 = 0x2111

    private let session: HIDPPSession
    private let deviceIndex: UInt8
    public let featureIndex: UInt8
    public let featureID: UInt16

    private var getFunctionID: UInt8 { featureID == Self.enhancedFeatureID ? 0x01 : 0x00 }
    private var setFunctionID: UInt8 { featureID == Self.enhancedFeatureID ? 0x02 : 0x01 }

    public init(session: HIDPPSession, deviceIndex: UInt8, featureIndex: UInt8,
                featureID: UInt16 = SmartShiftControls.featureID) {
        self.session = session
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
        self.featureID = featureID
    }

    public func getRatchetControlMode() throws -> SmartShiftStatus? {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: getFunctionID),
              resp.count >= 7 else { return nil }
        return SmartShiftStatus(wheelMode: resp[4], autoDisengage: resp[5],
                                autoDisengageDefault: resp[6])
    }

    public func setRatchetControlMode(status: SmartShiftStatus) throws {
        _ = try session.request(deviceIndex: deviceIndex,
                                featureIndex: featureIndex,
                                functionID: setFunctionID,
                                params: [status.wheelMode, status.autoDisengage,
                                         status.autoDisengageDefault])
    }
}
