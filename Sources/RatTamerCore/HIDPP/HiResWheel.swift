import Foundation

public struct WheelInfo: Equatable {
    public let multiplier: UInt8
    public let hasInvert: Bool
    public let hasSwitch: Bool

    public init(multiplier: UInt8, hasInvert: Bool, hasSwitch: Bool) {
        self.multiplier = multiplier
        self.hasInvert = hasInvert
        self.hasSwitch = hasSwitch
    }
}

public struct WheelModeInfo: Equatable {
    public let inverted: Bool
    public let highResolution: Bool
    public let diverted: Bool

    public init(inverted: Bool, highResolution: Bool, diverted: Bool) {
        self.inverted = inverted
        self.highResolution = highResolution
        self.diverted = diverted
    }
}

public final class HiResWheel {
    public static let featureID: UInt16 = 0x2121

    private let session: HIDPPSession
    private let deviceIndex: UInt8
    private let featureIndex: UInt8

    public init(session: HIDPPSession, deviceIndex: UInt8, featureIndex: UInt8) {
        self.session = session
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
    }

    public func getInfo() throws -> WheelInfo {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x00),
              resp.count >= 6 else {
            throw NSError(domain: "HiResWheel", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "short response"])
        }
        let flags = resp[5]
        return WheelInfo(multiplier: resp[4],
                         hasInvert: (flags >> 3) & 1 == 1,
                         hasSwitch: (flags >> 2) & 1 == 1)
    }

    public func getWheelMode() throws -> WheelModeInfo {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x01),
              resp.count >= 5 else {
            throw NSError(domain: "HiResWheel", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "short response"])
        }
        let mode = resp[4]
        return WheelModeInfo(inverted: (mode >> 2) & 1 == 1,
                             highResolution: (mode >> 1) & 1 == 1,
                             diverted: mode & 1 == 1)
    }

    public func setInverted(_ inverted: Bool) throws {
        var mode: UInt8 = 0
        if let resp = try session.request(deviceIndex: deviceIndex,
                                          featureIndex: featureIndex,
                                          functionID: 0x01),
           resp.count >= 5 {
            mode = resp[4]
        }
        if inverted {
            mode |= 0x04
        } else {
            mode &= ~0x04
        }
        _ = try session.request(deviceIndex: deviceIndex,
                                featureIndex: featureIndex,
                                functionID: 0x02,
                                params: [mode, 0x00, 0x00])
    }
}
