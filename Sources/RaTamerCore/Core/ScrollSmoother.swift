import Foundation
import os

/// Pure, clock-injected wheel smoother. No timers, no I/O — the caller feeds
/// raw wheel movements and ticks at a fixed rate; both return the pixels to
/// post right now. Time comes from the caller so tests use fictional clocks.
public final class ScrollSmoother {
    public struct Parameters: Equatable, Codable {
        public var multiplier: UInt8
        public var momentumEnabled: Bool
        public var invert: Bool
        public var maxBoost: Double
        public var momentumDecay: Double
        public var pixelsPerNotch: Double
        public var accelerationWindow: TimeInterval
        public var feedGapTimeout: TimeInterval
        public var momentumStopThreshold: Double
        public var bounceWindow: TimeInterval
        public var bounceRatio: Double
        public var bounceDamping: Double
        public var reversalConfirmation: Int
        public var directionThreshold: Double
        /// When true, feed accumulates into a target and tick glides the
        /// output toward it with an exponential ease-out (MOS-style).
        public var smoothingEnabled: Bool
        /// Fraction of the remaining distance approached per tick (120 Hz).
        public var smoothFraction: Double
        /// Distance below which the glide emits the remainder and stops.
        public var glideStopThreshold: Double

        public init(multiplier: UInt8,
                    momentumEnabled: Bool,
                    invert: Bool,
                    maxBoost: Double = ScrollSmoother.defaultMaxBoost,
                    momentumDecay: Double = ScrollSmoother.defaultMomentumDecay,
                    pixelsPerNotch: Double = ScrollSmoother.defaultPixelsPerNotch,
                    accelerationWindow: TimeInterval = ScrollSmoother.defaultAccelerationWindow,
                    feedGapTimeout: TimeInterval = ScrollSmoother.defaultFeedGapTimeout,
                    momentumStopThreshold: Double = ScrollSmoother.defaultMomentumStopThreshold,
                    bounceWindow: TimeInterval = ScrollSmoother.defaultBounceWindow,
                    bounceRatio: Double = ScrollSmoother.defaultBounceRatio,
                    bounceDamping: Double = ScrollSmoother.defaultBounceDamping,
                    reversalConfirmation: Int = ScrollSmoother.defaultReversalConfirmation,
                    directionThreshold: Double = ScrollSmoother.defaultDirectionThreshold,
                    smoothingEnabled: Bool = false,
                    smoothFraction: Double = ScrollSmoother.defaultSmoothFraction,
                    glideStopThreshold: Double = ScrollSmoother.defaultGlideStopThreshold) {
            self.multiplier = multiplier
            self.momentumEnabled = momentumEnabled
            self.invert = invert
            self.maxBoost = maxBoost
            self.momentumDecay = momentumDecay
            self.pixelsPerNotch = pixelsPerNotch
            self.accelerationWindow = accelerationWindow
            self.feedGapTimeout = feedGapTimeout
            self.momentumStopThreshold = momentumStopThreshold
            self.bounceWindow = bounceWindow
            self.bounceRatio = bounceRatio
            self.bounceDamping = bounceDamping
            self.reversalConfirmation = reversalConfirmation
            self.directionThreshold = directionThreshold
            self.smoothingEnabled = smoothingEnabled
            self.smoothFraction = smoothFraction
            self.glideStopThreshold = glideStopThreshold
        }
    }

    /// Base pixels emitted per full notch (deltaV == multiplier).
    public static let defaultPixelsPerNotch: Double = 10
    /// Feeds arriving inside this window are considered fast and get boosted.
    public static let defaultAccelerationWindow: TimeInterval = 0.05
    /// Max multiplier applied to a feed arriving ~instantly.
    public static let defaultMaxBoost: Double = 3.0
    /// Time without a feed before momentum may run.
    public static let defaultFeedGapTimeout: TimeInterval = 0.08
    /// Exponential decay per tick (120 Hz).
    public static let defaultMomentumDecay: Double = 0.85
    /// Below this absolute velocity momentum stops.
    public static let defaultMomentumStopThreshold: Double = 0.1
    /// Opposite-direction deltas arriving within this window of the last
    /// accepted feed are treated as mechanical detent bounce (ratcheted wheel).
    public static let defaultBounceWindow: TimeInterval = 0.15
    /// Bounces smaller than this fraction of the last accepted magnitude are
    /// strongly attenuated; bigger opposite pulses pass but still need
    /// confirmation before flipping the dominant direction. The MX Master
    /// ratchet bounce measures ~75–85% of the main pulse, so the ratio must
    /// sit above that to classify the rebound as bounce instead of reversal.
    public static let defaultBounceRatio: Double = 0.9
    /// Attenuation applied to detected bounces.
    public static let defaultBounceDamping: Double = 0.15
    /// Consecutive opposite pulses required to accept a direction reversal.
    /// The ratcheted MX Master can emit two consecutive opposite pulses when a
    /// tooth settles between grooves, so three are required to distinguish a
    /// real reversal (which produces a sustained run of opposite pulses) from
    /// mechanical jitter.
    public static let defaultReversalConfirmation: Int = 3
    /// Minimum magnitude for a feed to establish/refresh the dominant direction.
    public static let defaultDirectionThreshold: Double = 1.0
    /// Glide ease-out fraction per tick at 120 Hz (≈ Mos Duration 3.0).
    public static let defaultSmoothFraction: Double = 0.13
    /// Consensus stop epsilon from SmoothScroll / LinearMouse.
    public static let defaultGlideStopThreshold: Double = 0.5

    /// The pixels this wheel movement would produce natively, before any
    /// smoothing, boost or stabilization: notches × pixels per notch.
    public func rawPixels(for movement: WheelMovement) -> Double {
        let notches = Double(movement.deltaV) / Double(max(1, parameters.multiplier))
        return notches * parameters.pixelsPerNotch
    }

    public var parameters: Parameters

    private var lastFeedAt: Date?
    private var velocity: Double = 0
    private var direction: Int = 0
    private var oppositeCount = 0
    private var lastAcceptedAt: Date?
    private var lastAcceptedMagnitude: Double = 0
    private var target: Double = 0
    private var current: Double = 0
    private var carry: Double = 0

    public init(parameters: Parameters) {
        self.parameters = parameters
    }

    /// Converts a wheel movement to pixels. When both momentum and smoothing
    /// are disabled (Native), the pixels are passed through untouched — no
    /// boost, no bounce stabilization — but the configured invert is still
    /// applied (software-side direction). Otherwise applies the detent-bounce
    /// stabilization, seeds momentum, and returns the pixels to post now.
    @discardableResult
    public func feed(_ movement: WheelMovement, at now: Date) -> Double {
        let raw = rawPixels(for: movement)
        if !parameters.momentumEnabled && !parameters.smoothingEnabled {
            return applyInvert(raw)
        }
        let (stabilizedPixels, isBounce, reversed, accepted) = stabilized(raw, at: now)
        var pixels = stabilizedPixels
        if let last = lastFeedAt {
            let dt = now.timeIntervalSince(last)
            if dt > 0 && dt < parameters.accelerationWindow {
                let t = dt / parameters.accelerationWindow
                let boost = 1 + (parameters.maxBoost - 1) * (1 - t)
                pixels *= boost
            }
        }
        lastFeedAt = now
        if parameters.smoothingEnabled {
            if reversed {
                current = 0
                target = 0
                carry = 0
            }
            if accepted && !isBounce {
                target += pixels
            }
            return 0
        }
        if !isBounce {
            velocity = pixels
        }
        return applyInvert(pixels)
    }

    private static let debugLog = Logger(subsystem: "com.rattamer", category: "smoothdebug")
    private static let enableDebugLogging = false

    /// Stabilizes a raw pixel value against the mechanical detent bounce of a
    /// ratcheted wheel: small opposite-direction pulses arriving shortly after
    /// the last accepted feed are attenuated and a reversal is only accepted
    /// after `reversalConfirmation` consecutive opposite pulses. Returns the
    /// stabilized pixels and whether this feed was detected as a bounce (in
    /// which case it must not reseed momentum).
    private func stabilized(_ raw: Double, at now: Date)
        -> (pixels: Double, isBounce: Bool, reversed: Bool, accepted: Bool) {
        if Self.enableDebugLogging {
            #if DEBUG
        Self.debugLog.info("stabilized raw=\(raw, format: .fixed(precision: 1)) dir=\(self.direction) oppCount=\(self.oppositeCount) lastMag=\(self.lastAcceptedMagnitude, format: .fixed(precision: 1)) window=\(self.parameters.bounceWindow) ratio=\(self.parameters.bounceRatio)")
        #endif
        }
        var pixels = raw
        let sign = raw > 0 ? 1 : (raw < 0 ? -1 : 0)
        let directionBefore = direction
        guard direction != 0, sign != 0 else {
            if sign != 0, abs(pixels) >= parameters.directionThreshold {
                direction = sign
                lastAcceptedAt = now
                lastAcceptedMagnitude = abs(pixels)
            }
            oppositeCount = 0
            return (pixels, false, false, directionBefore == 0 || sign == directionBefore)
        }
        if sign == direction {
            oppositeCount = 0
            if abs(pixels) >= parameters.directionThreshold {
                direction = sign
                lastAcceptedAt = now
                lastAcceptedMagnitude = abs(pixels)
            }
            return (pixels, false, false, true)
        }
        // Opposite direction. The ratcheted MX Master emits isolated opposite
        // pulses at arbitrary delays as a tooth settles between the grooves,
        // so a single opposite pulse — however large — is never a reversal:
        // only `reversalConfirmation` consecutive opposite pulses flip the
        // dominant direction. Every opposite pulse counts toward confirmation
        // (and resets on the next dominant-direction pulse), but while
        // unconfirmed it is damped so it never emits backward scroll, reseeds
        // backward momentum, or feeds the glide target.
        oppositeCount += 1
        if oppositeCount >= parameters.reversalConfirmation {
            oppositeCount = 0
            direction = sign
            lastAcceptedAt = now
            lastAcceptedMagnitude = abs(pixels)
            return (pixels, false, true, true)
        }
        pixels *= parameters.bounceDamping
        return (pixels, true, false, false)
    }

    /// Returns decaying momentum pixels, or 0 when momentum is off, the wheel
    /// is still being fed, or velocity has drained below the stop threshold.
    @discardableResult
    public func tick(at now: Date) -> Double {
        if parameters.smoothingEnabled {
            return glideTick()
        }
        guard parameters.momentumEnabled else { return 0 }
        if let last = lastFeedAt, now.timeIntervalSince(last) < parameters.feedGapTimeout {
            return 0
        }
        guard abs(velocity) > parameters.momentumStopThreshold else {
            velocity = 0
            return 0
        }
        let out = velocity
        velocity *= parameters.momentumDecay
        return applyInvert(out)
    }

    private func glideTick() -> Double {
        let remaining = target - current
        if abs(remaining) <= parameters.glideStopThreshold {
            target = 0
            current = 0
            carry = 0
            return applyInvert(remaining)
        }
        var step = remaining * parameters.smoothFraction
        if abs(step) < 1 && abs(remaining) >= 1 {
            step = remaining > 0 ? 1 : -1
        } else if step == 0 {
            // smoothFraction == 0 (or a sub-pixel remainder): emit the
            // remainder in one tick so the glide always converges.
            step = remaining
        }
        carry += step - step.rounded()
        step = step.rounded()
        if abs(carry) >= 1 {
            let whole = carry > 0 ? 1.0 : -1.0
            step += whole
            carry -= whole
        }
        current += step
        return applyInvert(step)
    }

    public func reset() {
        lastFeedAt = nil
        velocity = 0
        direction = 0
        oppositeCount = 0
        lastAcceptedAt = nil
        lastAcceptedMagnitude = 0
        target = 0
        current = 0
        carry = 0
    }

    /// Parameter-change reset: drops momentum and anti-reversal state but
    /// keeps an in-flight glide (target/current/carry) so scrolling continues
    /// seamlessly under the new parameters.
    public func softReset() {
        velocity = 0
        direction = 0
        oppositeCount = 0
        lastAcceptedAt = nil
        lastAcceptedMagnitude = 0
    }

    /// Whether the smoother still has motion to emit: a glide target being
    /// drained, or momentum waiting out its feed gap / still above the stop
    /// threshold. When false, the coordinator can stop its tick timer.
    public func hasPendingWork(at now: Date) -> Bool {
        if parameters.smoothingEnabled {
            return target != 0
        }
        guard parameters.momentumEnabled else { return false }
        if let last = lastFeedAt, now.timeIntervalSince(last) < parameters.feedGapTimeout {
            return true
        }
        return abs(velocity) > parameters.momentumStopThreshold
    }

    private func applyInvert(_ value: Double) -> Double {
        parameters.invert ? -value : value
    }
}
