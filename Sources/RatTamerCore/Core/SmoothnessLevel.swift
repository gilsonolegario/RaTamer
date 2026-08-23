import Foundation

/// Named preset anchors on the smoothness curve. Each preset is a level; the
/// level is the single source of truth that derives all tuning parameters.
public enum SmoothnessPreset: String, CaseIterable {
    case native, smooth, glide, mos, soft, rat, warm, flow, fluid

    public var level: Double {
        switch self {
        case .native: return 0
        case .smooth: return 35
        case .glide: return 60
        case .mos: return 80
        case .soft: return 84
        case .rat: return 87
        case .warm: return 89
        case .flow: return 90
        case .fluid: return 100
        }
    }

    public var displayName: String {
        switch self {
        case .native: return "Native"
        case .smooth: return "Smooth"
        case .glide: return "Glide"
        case .mos: return "Mos"
        case .soft: return "Soft"
        case .rat: return "RaT"
        case .warm: return "Warm"
        case .flow: return "Flow"
        case .fluid: return "Fluid"
        }
    }

    public init?(level: Double) {
        guard let match = Self.allCases.first(where: { $0.level == level }) else { return nil }
        self = match
    }
}

/// Pure mapping from a single 0-100 smoothness level to the tuning parameters
/// of `ScrollSmoother`. The curve is piecewise-linear over nine preset anchors:
/// Native(0), Smooth(35), Glide(60), Mos(80), Soft(84), RaT(87), Warm(89),
/// Flow(90), Fluid(100).
/// Continuous fields interpolate between adjacent anchors; boolean fields take
/// the nearest anchor's value (ties resolve to the higher level).
public enum SmoothnessLevel {
    public static let min: Double = 0
    public static let max: Double = 100
    public static let defaultValue: Double = SmoothnessPreset.rat.level

    public struct Anchor {
        public let level: Double
        public let momentumEnabled: Bool
        public let smoothingEnabled: Bool
        public let pixelsPerNotch: Double
        public let maxBoost: Double
        public let momentumDecay: Double
        public let smoothFraction: Double
        public let glideStopThreshold: Double

        public init(level: Double,
                    momentumEnabled: Bool,
                    smoothingEnabled: Bool,
                    pixelsPerNotch: Double,
                    maxBoost: Double,
                    momentumDecay: Double,
                    smoothFraction: Double,
                    glideStopThreshold: Double) {
            self.level = level
            self.momentumEnabled = momentumEnabled
            self.smoothingEnabled = smoothingEnabled
            self.pixelsPerNotch = pixelsPerNotch
            self.maxBoost = maxBoost
            self.momentumDecay = momentumDecay
            self.smoothFraction = smoothFraction
            self.glideStopThreshold = glideStopThreshold
        }
    }

    public static let anchors: [Anchor] = [
        Anchor(level: 0, momentumEnabled: false, smoothingEnabled: false,
               pixelsPerNotch: 48, maxBoost: 1.0, momentumDecay: 0.70,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 35, momentumEnabled: true, smoothingEnabled: false,
               pixelsPerNotch: 55, maxBoost: 2.5, momentumDecay: 0.88,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 60, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 90, maxBoost: 1.6, momentumDecay: 0.85,
               smoothFraction: 0.14, glideStopThreshold: 0.5),
        Anchor(level: 80, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 115, maxBoost: 1.2, momentumDecay: 0.85,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 84, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 122, maxBoost: 1.15, momentumDecay: 0.85,
               smoothFraction: 0.13, glideStopThreshold: 0.5),
        Anchor(level: 87, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 128, maxBoost: 1.12, momentumDecay: 0.85,
               smoothFraction: 0.125, glideStopThreshold: 0.5),
        Anchor(level: 89, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 133, maxBoost: 1.1, momentumDecay: 0.85,
               smoothFraction: 0.12, glideStopThreshold: 0.5),
        Anchor(level: 90, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 140, maxBoost: 1.1, momentumDecay: 0.85,
               smoothFraction: 0.12, glideStopThreshold: 0.5),
        Anchor(level: 100, momentumEnabled: false, smoothingEnabled: true,
               pixelsPerNotch: 165, maxBoost: 1.0, momentumDecay: 0.85,
               smoothFraction: 0.11, glideStopThreshold: 0.5),
    ]

    public static func clamped(_ level: Double) -> Double {
        Swift.min(Swift.max(level, min), max)
    }

    public static func maxBoost(_ level: Double) -> Double {
        interpolate(level, keyPath: \.maxBoost)
    }

    public static func momentumDecay(_ level: Double) -> Double {
        interpolate(level, keyPath: \.momentumDecay)
    }

    public static func pixelsPerNotch(_ level: Double) -> Double {
        interpolate(level, keyPath: \.pixelsPerNotch)
    }

    public static func smoothFraction(_ level: Double) -> Double {
        interpolate(level, keyPath: \.smoothFraction)
    }

    public static func glideStopThreshold(_ level: Double) -> Double {
        interpolate(level, keyPath: \.glideStopThreshold)
    }

    public static func momentumEnabled(_ level: Double) -> Bool {
        nearest(level, keyPath: \.momentumEnabled)
    }

    public static func smoothingEnabled(_ level: Double) -> Bool {
        nearest(level, keyPath: \.smoothingEnabled)
    }

    /// Level where smoothing (glide) first turns on: the midpoint between the
    /// last off-anchor and the first on-anchor (Smooth→Glide = 47.5).
    public static var smoothingStartLevel: Double {
        let sorted = anchors.sorted { $0.level < $1.level }
        for (lower, upper) in zip(sorted, sorted.dropFirst()) {
            if !lower.smoothingEnabled && upper.smoothingEnabled {
                return (lower.level + upper.level) / 2
            }
        }
        return min
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
            momentumDecay: momentumDecay(l),
            pixelsPerNotch: pixelsPerNotch(l),
            accelerationWindow: ScrollSmoother.defaultAccelerationWindow,
            feedGapTimeout: ScrollSmoother.defaultFeedGapTimeout,
            momentumStopThreshold: ScrollSmoother.defaultMomentumStopThreshold,
            bounceWindow: ScrollSmoother.defaultBounceWindow,
            bounceRatio: ScrollSmoother.defaultBounceRatio,
            bounceDamping: ScrollSmoother.defaultBounceDamping,
            reversalConfirmation: ScrollSmoother.defaultReversalConfirmation,
            directionThreshold: ScrollSmoother.defaultDirectionThreshold,
            smoothingEnabled: smoothingEnabled(l),
            smoothFraction: smoothFraction(l),
            glideStopThreshold: glideStopThreshold(l))
    }

    private static func interpolate(_ level: Double, keyPath: KeyPath<Anchor, Double>) -> Double {
        let l = clamped(level)
        guard let lower = anchors.last(where: { $0.level <= l }),
              let upper = anchors.first(where: { $0.level >= l }) else {
            return anchors[0][keyPath: keyPath]
        }
        if lower.level == upper.level { return lower[keyPath: keyPath] }
        let t = (l - lower.level) / (upper.level - lower.level)
        return lower[keyPath: keyPath] + (upper[keyPath: keyPath] - lower[keyPath: keyPath]) * t
    }

    private static func nearest(_ level: Double, keyPath: KeyPath<Anchor, Bool>) -> Bool {
        let l = clamped(level)
        return anchors.min { lhs, rhs in
            let ld = abs(lhs.level - l)
            let rd = abs(rhs.level - l)
            return ld < rd || (ld == rd && lhs.level > rhs.level)
        }?[keyPath: keyPath] ?? anchors[0][keyPath: keyPath]
    }
}
