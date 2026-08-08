import Foundation

public final class DeviceName {
    public static let featureID: UInt16 = 0x0005

    private let session: HIDPPSession
    private let deviceIndex: UInt8
    public let featureIndex: UInt8

    public init(session: HIDPPSession, deviceIndex: UInt8, featureIndex: UInt8) {
        self.session = session
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
    }

    /// fn 0: getDeviceNameCount — device name length in bytes.
    public func getNameCount() throws -> Int {
        guard let resp = try session.request(deviceIndex: deviceIndex,
                                             featureIndex: featureIndex,
                                             functionID: 0x00),
              resp.count >= 5 else { return 0 }
        return Int(resp[4])
    }

    /// fn 1: getDeviceName — reads 16-byte chunks until the full name is assembled.
    public func getName() throws -> String? {
        let nameLength = try getNameCount()
        guard nameLength > 0 else { return nil }
        var name = ""
        var offset = 0
        while name.utf8.count < nameLength {
            let lo = UInt8(offset & 0xFF)
            let hi = UInt8((offset >> 8) & 0xFF)
            guard let resp = try session.request(deviceIndex: deviceIndex,
                                                 featureIndex: featureIndex,
                                                 functionID: 0x01,
                                                 params: [lo, hi]),
                  resp.count > 4 else { return nil }
            let remaining = nameLength - name.utf8.count
            let end = min(resp.count, 4 + min(16, remaining))
            name += String(decoding: resp[4..<end], as: UTF8.self)
            offset += 16
        }
        return name
    }
}
