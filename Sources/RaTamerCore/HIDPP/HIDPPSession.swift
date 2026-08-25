import Foundation

public enum HIDPPSessionError: Error {
    case noResponse
}

public final class HIDPPSession {
    public let device: HIDDevice
    public let softwareID: UInt8
    public var productName: String? { device.productName }

    /// Receivers report their own HID name ("USB Receiver"); the real product
    /// name comes from HID++ feature 0x0005. Returns the IOKit name unless it
    /// is nil or a known receiver name, in which case it queries the device.
    public func readProductName(deviceIndex: UInt8) throws -> String? {
        let name = device.productName
        let receiverNames: Set<String> = ["USB Receiver", "Logi Receiver", "Receiver"]
        if let name, !receiverNames.contains(name) { return name }
        guard let featureIndex = try getFeatureIndex(featureID: DeviceName.featureID, deviceIndex: deviceIndex),
              featureIndex != 0 else { return name }
        let service = DeviceName(session: self, deviceIndex: deviceIndex, featureIndex: featureIndex)
        return try service.getName() ?? name
    }

    private var isClosed = false

    public init(device: HIDDevice, softwareID: UInt8 = 1) {
        self.device = device
        self.softwareID = softwareID
    }

    public func sendShort(
        deviceIndex: UInt8, featureIndex: UInt8,
        functionID: UInt8, params: [UInt8] = []
    ) throws {
        let bytes = HIDPP.buildShort(
            deviceIndex: deviceIndex, featureIndex: featureIndex,
            functionID: functionID, softwareID: softwareID,
            params: params
        )
        try device.write(bytes)
    }

    public func sendLong(
        deviceIndex: UInt8, featureIndex: UInt8,
        functionID: UInt8, params: [UInt8] = []
    ) throws {
        let bytes = HIDPP.buildLong(
            deviceIndex: deviceIndex, featureIndex: featureIndex,
            functionID: functionID, softwareID: softwareID,
            params: params
        )
        try device.write(bytes)
    }

    public func readReport(timeout: TimeInterval) throws -> [UInt8]? {
        return try device.read(timeout: timeout)
    }

    /// Wakes a thread blocked in `readReport` so the engine's monitor loop can
    /// exit at teardown instead of polling with a short timeout.
    public func wake() {
        device.wake()
    }

    /// Returns a consumed report's storage to the device's buffer pool.
    public func recycle(_ bytes: inout [UInt8]) {
        device.recycle(&bytes)
    }

    public func request(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        functionID: UInt8,
        params: [UInt8] = [],
        timeout: TimeInterval = 0.5
    ) throws -> [UInt8]? {
        guard device.beginRequest(timeout: timeout) else {
            throw HIDPPSessionError.noResponse
        }
        defer { device.endRequest() }
        try sendLong(deviceIndex: deviceIndex, featureIndex: featureIndex,
                     functionID: functionID, params: params)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            guard let resp = try device.readForRequest(timeout: min(0.1, remaining)) else { continue }
            guard resp.count >= 4,
                  resp[1] == deviceIndex,
                  resp[2] == featureIndex,
                  resp[3] >> 4 == functionID else { continue }
            let sw = resp[3] & 0x0F
            guard sw == softwareID || sw == 0 else { continue }
            return resp
        }
        return nil
    }

    public func getFeatureIndex(featureID: UInt16, deviceIndex: UInt8) throws -> UInt8? {
        let hi = UInt8((featureID >> 8) & 0xFF)
        let lo = UInt8(featureID & 0xFF)
        for _ in 0..<3 {
            guard let resp = try request(deviceIndex: deviceIndex, featureIndex: 0,
                                         functionID: 0x00, params: [hi, lo, 0x00]),
                  resp.count >= 5 else { continue }
            let featureIndex = resp[4]
            if featureIndex == 0 { return nil }
            return featureIndex
        }
        return nil
    }

    public func ping(deviceIndex: UInt8) throws -> Bool {
        // Probes whether a device exists at this index. The Root feature
        // always answers with feature index 0, so any matching response means
        // the device is present (mirrors the Python `fi is not None or resp`).
        // Ping is a request/reply exchange, so it uses the request read path
        // and must not be blocked by another request in flight.
        guard device.beginRequest(timeout: 0.4) else {
            throw HIDPPSessionError.noResponse
        }
        defer { device.endRequest() }
        try sendShort(deviceIndex: deviceIndex, featureIndex: 0,
                      functionID: 0x00, params: [0x00, 0x00, 0x00])
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            guard let resp = try device.readForRequest(timeout: min(0.1, remaining)) else { continue }
            guard resp.count >= 4,
                  (resp[0] == HIDPP.reportIDShort || resp[0] == HIDPP.reportIDLong),
                  resp[1] == deviceIndex,
                  resp[2] == 0x00,
                  resp[3] >> 4 == 0x00 else { continue }
            let sw = resp[3] & 0x0F
            guard sw == softwareID || sw == 0 else { continue }
            return true
        }
        return false
    }

    /// Closes the underlying device exactly once. Safe to call repeatedly.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        device.close()
    }
}
