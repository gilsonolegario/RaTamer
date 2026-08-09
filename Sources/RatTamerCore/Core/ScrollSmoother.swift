import Foundation

/// Pure, clock-injected wheel smoother. No timers, no I/O — the caller feeds
/// raw wheel movements and ticks at a fixed rate; both return the pixels to
/// post right now. Time comes from the caller so tests use fictional clocks.
public final class ScrollSmoother {
    public struct Parameters: Equatable {
        public var multiplier: UInt8
        public var momentumEnabled: Bool
        public var invert: Bool

        public init(multiplier: UInt8, momentumEnabled: Bool, invert: Bool) {
            self.multiplier = multiplier
            self.momentumEnabled = momentumEnabled
            self.invert = invert
        }
    }

    /// Base pixels emitted per full notch (deltaV == multiplier).
    public static let pixelsPerNotch: Double = 10
    /// Feeds arriving inside this window are considered fast and get boosted.
    public static let accelerationWindow: TimeInterval = 0.05
    /// Max multiplier applied to a feed arriving ~instantly.
    public static let maxBoost: Double = 3.0
    /// Time without a feed before momentum may run.
    public static let feedGapTimeout: TimeInterval = 0.08
    /// Exponential decay per tick (120 Hz).
    public static let momentumDecay: Double = 0.85
    /// Below this absolute velocity momentum stops.
    public static let momentumStopThreshold: Double = 0.1

    public var parameters: Parameters

    private var lastFeedAt: Date?
    private var velocity: Double = 0

    public init(parameters: Parameters) {
        self.parameters = parameters
    }

    /// Converts a wheel movement to pixels, applies the acceleration curve,
    /// seeds momentum, and returns the pixels to post now.
    @discardableResult
    public func feed(_ movement: WheelMovement, at now: Date) -> Double {
        let notches = Double(movement.deltaV) / Double(max(1, parameters.multiplier))
        var pixels = notches * Self.pixelsPerNotch
        if let last = lastFeedAt {
            let dt = now.timeIntervalSince(last)
            if dt > 0 && dt < Self.accelerationWindow {
                let t = dt / Self.accelerationWindow
                let boost = 1 + (Self.maxBoost - 1) * (1 - t)
                pixels *= boost
            }
        }
        lastFeedAt = now
        velocity = pixels
        return applyInvert(pixels)
    }

    /// Returns decaying momentum pixels, or 0 when momentum is off, the wheel
    /// is still being fed, or velocity has drained below the stop threshold.
    @discardableResult
    public func tick(at now: Date) -> Double {
        guard parameters.momentumEnabled else { return 0 }
        if let last = lastFeedAt, now.timeIntervalSince(last) < Self.feedGapTimeout {
            return 0
        }
        guard abs(velocity) > Self.momentumStopThreshold else {
            velocity = 0
            return 0
        }
        let out = velocity
        velocity *= Self.momentumDecay
        return applyInvert(out)
    }

    public func reset() {
        lastFeedAt = nil
        velocity = 0
    }

    private func applyInvert(_ value: Double) -> Double {
        parameters.invert ? -value : value
    }
}
