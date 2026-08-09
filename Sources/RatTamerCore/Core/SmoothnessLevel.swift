import Foundation

/// Pure mapping from a single 0-100 smoothness level to the tuning parameters
/// of `ScrollSmoother`. Higher levels amplify more and glide longer. Anchors:
/// 0 = Discreta, 50 = Média (current defaults), 100 = Fluida.
public enum SmoothnessLevel {
    public static let min: Double = 0
    public static let max: Double = 100
    public static let defaultValue: Double = 50
    /// Momentum (glide) only engages at or above this level.
    public static let momentumOnThreshold: Double = 20

    /// maxBoost anchors: level -> value.
    public static let maxBoostAnchors: [(level: Double, value: Double)] = [
        (0, 1.5), (50, 3.0), (100, 5.0),
    ]
    /// momentumDecay anchors: level -> value.
    public static let momentumDecayAnchors: [(level: Double, value: Double)] = [
        (0, 0.70), (20, 0.75), (50, 0.85), (100, 0.92),
    ]

    public static func clamped(_ level: Double) -> Double {
        Swift.min(Swift.max(level, min), max)
    }

    public static func momentumEnabled(_ level: Double) -> Bool {
        clamped(level) >= momentumOnThreshold
    }

    public static func maxBoost(_ level: Double) -> Double {
        interpolate(anchors: maxBoostAnchors, level: clamped(level))
    }

    public static func momentumDecay(_ level: Double) -> Double {
        interpolate(anchors: momentumDecayAnchors, level: clamped(level))
    }

    public static func parameters(level: Double,
                                  multiplier: UInt8,
                                  invert: Bool) -> ScrollSmoother.Parameters {
        let l = clamped(level)
        return ScrollSmoother.Parameters(
            multiplier: multiplier,
            momentumEnabled: momentumEnabled(l),
            invert: invert,
            maxBoost: maxBoost(l),
            momentumDecay: momentumDecay(l))
    }

    private static func interpolate(anchors: [(level: Double, value: Double)],
                                    level: Double) -> Double {
        if level <= anchors[0].level { return anchors[0].value }
        if level >= anchors[anchors.count - 1].level { return anchors[anchors.count - 1].value }
        for i in 0..<(anchors.count - 1) {
            let a = anchors[i]
            let b = anchors[i + 1]
            if level >= a.level, level <= b.level {
                let t = (level - a.level) / (b.level - a.level)
                return a.value + (b.value - a.value) * t
            }
        }
        return anchors[anchors.count - 1].value
    }
}
