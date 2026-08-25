import Foundation

public struct ControlInfo: Equatable, Identifiable {
    public var id: UInt16 { cid }
    public let cid: UInt16
    public let taskID: UInt16
    public let flags: UInt8
    public let position: UInt8
    public let group: UInt8
    public let groupMask: UInt8

    public var isMouseButton: Bool { flags & 0x01 != 0 }
    public var isReprogrammable: Bool { flags & 0x10 != 0 }
    public var isDivertable: Bool { flags & 0x20 != 0 }

    public init(cid: UInt16, taskID: UInt16, flags: UInt8,
                position: UInt8, group: UInt8, groupMask: UInt8) {
        self.cid = cid
        self.taskID = taskID
        self.flags = flags
        self.position = position
        self.group = group
        self.groupMask = groupMask
    }
}

public final class ReprogrammableControls {
    public static let featureID: UInt16 = 0x1B04

    private let session: HIDPPSession
    private let deviceIndex: UInt8
    public let featureIndex: UInt8

    public init(session: HIDPPSession, deviceIndex: UInt8, featureIndex: UInt8) {
        self.session = session
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
    }

    public func getCount() throws -> Int {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex, functionID: 0x00),
              resp.count >= 5 else { return 0 }
        return Int(resp[4])
    }

    public func controlInfo(at index: Int) throws -> ControlInfo? {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x01,
                                             params: [UInt8(index)]),
              resp.count >= 13 else { return nil }
        let d = Array(resp.dropFirst(4))
        return ControlInfo(
            cid: UInt16(d[0]) << 8 | UInt16(d[1]),
            taskID: UInt16(d[2]) << 8 | UInt16(d[3]),
            flags: d[4], position: d[5], group: d[6], groupMask: d[7]
        )
    }

    public func enumerate() throws -> [ControlInfo] {
        let count = try getCount()
        var result: [ControlInfo] = []
        for index in 0..<count {
            if let info = try controlInfo(at: index) {
                result.append(info)
            }
        }
        return result
    }

    public func reportingFlags(cid: UInt16) throws -> (flags: UInt8, remap: UInt16)? {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x02,
                                             params: [UInt8(cid >> 8), UInt8(cid & 0xFF)]),
              resp.count >= 9 else { return nil }
        let d = Array(resp.dropFirst(4))
        return (flags: d[2], remap: UInt16(d[3]) << 8 | UInt16(d[4]))
    }

    /// Flag bits for the Reprogrammable Controls reporting flags byte, matching
    /// Solaar / mx-gestures: divert 0x01, divert-valid 0x02, raw XY 0x10, raw
    /// XY valid 0x20.
    public static let flagDivert: UInt8 = 0x01
    public static let flagDivertValid: UInt8 = 0x02
    public static let flagRawXY: UInt8 = 0x10
    public static let flagRawXYValid: UInt8 = 0x20

    public func setDiverted(cid: UInt16, diverted: Bool, rawXY: Bool = false) throws {
        var flags: UInt8 = diverted ? Self.flagDivert : 0x00
        flags |= Self.flagDivertValid
        if rawXY {
            flags |= Self.flagRawXYValid
            if diverted { flags |= Self.flagRawXY }
        }
        _ = try session.request(deviceIndex: deviceIndex,
                                featureIndex: featureIndex,
                                functionID: 0x03,
                                params: [UInt8(cid >> 8), UInt8(cid & 0xFF),
                                         flags, 0x00, 0x00])
    }

    public func setRemapped(cid: UInt16, target: UInt16) throws {
        let current = try reportingFlags(cid: cid)?.flags ?? 0x00
        _ = try session.request(deviceIndex: deviceIndex,
                                featureIndex: featureIndex,
                                functionID: 0x03,
                                params: [UInt8(cid >> 8), UInt8(cid & 0xFF),
                                         current, UInt8(target >> 8), UInt8(target & 0xFF)])
    }

    public func resetRemap(cid: UInt16) throws {
        try setRemapped(cid: cid, target: cid)
    }

    public static func parseDivertedEvent(_ bytes: [UInt8], deviceIndex: UInt8,
                                          featureIndex: UInt8) -> [UInt16]? {
        guard bytes.count >= 12,
              bytes[0] == HIDPP.reportIDLong,
              bytes[1] == deviceIndex,
              bytes[2] == featureIndex,
              bytes[3] == 0x00 else { return nil }
        var cids: [UInt16] = []
        for index in 0..<4 {
            let cid = UInt16(bytes[4 + index * 2]) << 8 | UInt16(bytes[5 + index * 2])
            if cid != 0 { cids.append(cid) }
        }
        return cids
    }

    /// Decode a diverted raw mouse XY event (event_id 0x1). Deltas are signed
    /// big-endian Int16: dx positive = right, dy positive = down (HID
    /// convention).
    public static func parseRawXYEvent(_ bytes: [UInt8], deviceIndex: UInt8,
                                       featureIndex: UInt8) -> (dx: Int16, dy: Int16)? {
        guard bytes.count >= 8,
              bytes[0] == HIDPP.reportIDLong,
              bytes[1] == deviceIndex,
              bytes[2] == featureIndex,
              bytes[3] == 0x10 else { return nil }
        let dx = Int16(bytes[4]) << 8 | Int16(bytes[5])
        let dy = Int16(bytes[6]) << 8 | Int16(bytes[7])
        return (dx, dy)
    }
}
