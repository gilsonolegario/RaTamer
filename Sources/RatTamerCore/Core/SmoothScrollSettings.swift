import Foundation

/// Resolves the persisted smooth-scroll state (`smoothScrollLevel` +
/// `smoothScrollAdvanced`) into a concrete `ScrollSmoother.Parameters`.
/// `level == nil` means "custom" (advanced diverges from the level).
/// When `advanced` is present it wins; otherwise the three level-linked
/// parameters are derived from the level. `multiplier`/`invert` are always
/// overwritten by the caller-provided values, never trusted from storage.
public struct SmoothScrollSettings: Equatable {
    public let level: Double?
    public let advanced: ScrollSmoother.Parameters?
    public let multiplier: UInt8
    public let invert: Bool

    public init(level: Double?,
                advanced: ScrollSmoother.Parameters?,
                multiplier: UInt8,
                invert: Bool) {
        self.level = level
        self.advanced = advanced
        self.multiplier = multiplier
        self.invert = invert
    }

    public var isCustom: Bool {
        guard let advanced else { return false }
        guard let level else { return true }
        let derived = SmoothnessLevel.parameters(level: level,
                                                 multiplier: multiplier,
                                                 invert: invert)
        return advanced.maxBoost != derived.maxBoost
            || advanced.momentumDecay != derived.momentumDecay
            || advanced.momentumEnabled != derived.momentumEnabled
            || advanced.smoothingEnabled != derived.smoothingEnabled
            || advanced.pixelsPerNotch != derived.pixelsPerNotch
            || advanced.smoothFraction != derived.smoothFraction
            || advanced.glideStopThreshold != derived.glideStopThreshold
    }

    public var parameters: ScrollSmoother.Parameters {
        if let advanced {
            var p = advanced
            p.multiplier = multiplier
            p.invert = invert
            return p
        }
        return SmoothnessLevel.parameters(level: level ?? SmoothnessLevel.defaultValue,
                                          multiplier: multiplier,
                                          invert: invert)
    }
}