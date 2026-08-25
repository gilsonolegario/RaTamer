import Foundation

public struct DeviceCapabilities: Equatable {
    public var hasReprogrammableControls: Bool
    public var hasBattery: Bool
    public var hasDPI: Bool
    public var hasSmartShift: Bool

    public init(hasReprogrammableControls: Bool, hasBattery: Bool, hasDPI: Bool, hasSmartShift: Bool) {
        self.hasReprogrammableControls = hasReprogrammableControls
        self.hasBattery = hasBattery
        self.hasDPI = hasDPI
        self.hasSmartShift = hasSmartShift
    }
}
