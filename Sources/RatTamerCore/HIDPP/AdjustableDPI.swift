import Foundation

public struct DPISensorInfo: Codable, Equatable {
    public var dpi: UInt16
    public var defaultDpi: UInt16

    public init(dpi: UInt16, defaultDpi: UInt16) {
        self.dpi = dpi
        self.defaultDpi = defaultDpi
    }
}

public final class AdjustableDPI {
    public static let featureID: UInt16 = 0x2201

    private let session: HIDPPSession
    private let deviceIndex: UInt8
    public let featureIndex: UInt8

    public init(session: HIDPPSession, deviceIndex: UInt8, featureIndex: UInt8) {
        self.session = session
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
    }

    public func getSensorCount() throws -> Int {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x00),
              resp.count >= 5 else { return 0 }
        return Int(resp[4])
    }

    public func getSensorDpiList(sensor: UInt8) throws -> [UInt16] {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x01,
                                             params: [sensor]),
              resp.count >= 5 else { return [] }
        var entries: [UInt16] = []
        var offset = 5
        while offset + 1 < resp.count {
            let value = UInt16(resp[offset]) << 8 | UInt16(resp[offset + 1])
            guard value != 0 else { break }
            entries.append(value)
            offset += 2
        }
        return Self.expand(entries)
    }

    public func getSensorDpi(sensor: UInt8) throws -> DPISensorInfo? {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x02,
                                             params: [sensor]),
              resp.count >= 7 else { return nil }
        return DPISensorInfo(
            dpi: UInt16(resp[5]) << 8 | UInt16(resp[6]),
            defaultDpi: resp.count >= 9 ? UInt16(resp[7]) << 8 | UInt16(resp[8]) : 0
        )
    }

    public func setSensorDpi(sensor: UInt8, dpi: UInt16) throws {
        _ = try session.request(deviceIndex: deviceIndex,
                                featureIndex: featureIndex,
                                functionID: 0x03,
                                params: [sensor, UInt8(dpi >> 8), UInt8(dpi & 0xFF)])
    }

    static func expand(_ entries: [UInt16]) -> [UInt16] {
        var result: [UInt16] = []
        var i = 0
        while i < entries.count {
            let value = entries[i]
            if value >> 13 == 0b111 {
                let step = Int(value & 0x1FFF)
                let end = Int(entries[i + 1])
                var current = Int(entries[i - 1]) + step
                while current <= end {
                    result.append(UInt16(current))
                    current += step
                }
                i += 2
            } else {
                result.append(value)
                i += 1
            }
        }
        return result
    }
}
