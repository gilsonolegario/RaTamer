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
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x01),
              resp.count >= 5 else {
            throw NSError(domain: "HiResWheel", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "read mode failed"])
        }
        var mode = resp[4]
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

    /// Sets the wheel target (native HID vs HID++ notification) and resolution
    /// (low vs high). Bit 2 (invert) is preserved from the current mode. With
    /// `target = true` the device stops emitting native HID wheel events, which
    /// is the double-scroll suppression mechanism.
    public func setWheelMode(highResolution: Bool, target: Bool) throws {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x01),
              resp.count >= 5 else {
            throw NSError(domain: "HiResWheel", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "read mode failed"])
        }
        var mode = resp[4]
        if highResolution {
            mode |= 0x02
        } else {
            mode &= ~0x02
        }
        if target {
            mode |= 0x01
        } else {
            mode &= ~0x01
        }
        _ = try session.request(deviceIndex: deviceIndex,
                                featureIndex: featureIndex,
                                functionID: 0x02,
                                params: [mode, 0x00, 0x00])
    }

    /// Decodes a wheelMovement notification (notification ID 0x00).
    public static func parseWheelMovement(_ bytes: [UInt8],
                                          deviceIndex: UInt8,
                                          featureIndex: UInt8) -> WheelMovement? {
        guard bytes.count >= 7,
              bytes[0] == HIDPP.reportIDLong,
              bytes[1] == deviceIndex,
              bytes[2] == featureIndex,
              bytes[3] == 0x00 else { return nil }
        let flags = bytes[4]
        let periods = flags & 0x0F
        let resolution = (flags >> 4) & 1 == 1
        let deltaV = Int16(bitPattern: UInt16(bytes[5]) << 8 | UInt16(bytes[6]))
        return WheelMovement(deltaV: deltaV, periods: periods, resolution: resolution)
    }
}

public struct WheelMovement: Equatable {
    public let deltaV: Int16
    public let periods: UInt8
    public let resolution: Bool

    public init(deltaV: Int16, periods: UInt8, resolution: Bool) {
        self.deltaV = deltaV
        self.periods = periods
        self.resolution = resolution
    }
}
