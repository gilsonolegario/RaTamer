import Foundation

public enum HIDPP {
    public static let reportIDShort: UInt8 = 0x10
    public static let reportIDLong: UInt8 = 0x11
    public static let featureRoot: UInt16 = 0x0000
    public static let featureSpecialKeysButtons: UInt16 = 0x1B04
    public static let buttonFunctionID: UInt8 = 0x10
    public static let taskSmartShift: UInt16 = 0x009D

    public static func buildShort(
        deviceIndex: UInt8, featureIndex: UInt8,
        functionID: UInt8, softwareID: UInt8,
        params: [UInt8]
    ) -> [UInt8] {
        return build(deviceIndex: deviceIndex, featureIndex: featureIndex,
                     functionID: functionID, softwareID: softwareID,
                     params: params, payloadSize: 6)
    }

    public static func buildLong(
        deviceIndex: UInt8, featureIndex: UInt8,
        functionID: UInt8, softwareID: UInt8,
        params: [UInt8]
    ) -> [UInt8] {
        return build(deviceIndex: deviceIndex, featureIndex: featureIndex,
                     functionID: functionID, softwareID: softwareID,
                     params: params, payloadSize: 19)
    }

    private static func build(
        deviceIndex: UInt8, featureIndex: UInt8,
        functionID: UInt8, softwareID: UInt8,
        params: [UInt8], payloadSize: Int
    ) -> [UInt8] {
        var body: [UInt8] = [
            deviceIndex, featureIndex,
            (functionID << 4) | (softwareID & 0x0F)
        ]
        body.append(contentsOf: params)
        let padded = Array((body + [UInt8](repeating: 0, count: payloadSize)).prefix(payloadSize))
        let reportID: UInt8 = payloadSize == 6 ? reportIDShort : reportIDLong
        return [reportID] + padded
    }
}

public enum ControlTaskName {
    public static func name(for taskID: UInt16) -> String {
        switch taskID {
        case 0x0038: return "Left Button"
        case 0x0039: return "Right Button"
        case 0x003A: return "Middle Button"
        case 0x003C: return "Back"
        case 0x003E: return "Forward"
        case 0x009D: return "Scroll Mode (SmartShift)"
        case 0x00A9: return "Thumb / Gesture"
        case 0x00B4: return "Virtual Gesture"
        default: return String(format: "Control 0x%04X", taskID)
        }
    }
}
