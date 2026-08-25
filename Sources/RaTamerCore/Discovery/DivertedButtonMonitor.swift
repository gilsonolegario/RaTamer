import Foundation

public final class DivertedButtonMonitor {
    public var onControlPressed: ((_ cid: UInt16) -> Void)?
    public var onControlReleased: ((_ cid: UInt16) -> Void)?
    public var onRawXY: ((_ dx: Int16, _ dy: Int16) -> Void)?
    public var onWheelMovement: ((WheelMovement) -> Void)?

    public private(set) var pressed = Set<UInt16>()

    private let deviceIndex: UInt8
    private let featureIndex: UInt8
    private let wheelFeatureIndex: UInt8?

    public init(deviceIndex: UInt8, featureIndex: UInt8, wheelFeatureIndex: UInt8? = nil) {
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
        self.wheelFeatureIndex = wheelFeatureIndex
    }

    @discardableResult
    public func feed(_ bytes: [UInt8]) -> Bool {
        if let wheelFeatureIndex,
           let movement = HiResWheel.parseWheelMovement(
               bytes, deviceIndex: deviceIndex, featureIndex: wheelFeatureIndex
           ) {
            onWheelMovement?(movement)
            return true
        }
        if let raw = ReprogrammableControls.parseRawXYEvent(
            bytes, deviceIndex: deviceIndex, featureIndex: featureIndex
        ) {
            onRawXY?(raw.dx, raw.dy)
            return true
        }
        guard let cids = ReprogrammableControls.parseDivertedEvent(
            bytes, deviceIndex: deviceIndex, featureIndex: featureIndex
        ) else { return false }
        let now = Set(cids)
        for cid in cids where !pressed.contains(cid) {
            onControlPressed?(cid)
        }
        for cid in pressed.subtracting(now) {
            onControlReleased?(cid)
        }
        pressed = now
        return true
    }
}
