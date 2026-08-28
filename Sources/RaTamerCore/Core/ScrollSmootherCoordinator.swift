import Foundation
import os

/// Owns the scroll tick timer, feeds the pure `ScrollSmoother` with wheel
/// movements, and posts the resulting deltas via the injected poster closure.
/// The timer is armed lazily on the first wheel movement and stops itself as
/// soon as the smoother has no motion to emit, so an idle wheel does not wake
/// the process at 120 Hz. All smoother access happens on this coordinator's
/// private queue so the HID++ loop thread and the timer never race.
public final class ScrollSmootherCoordinator {
    private static let log = Logger(subsystem: "com.rattamer", category: "smoothscroll")
    private static let tickInterval: TimeInterval = 1.0 / 120.0

    private let smoother: ScrollSmoother
    private let now: () -> Date
    private let poster: (Double) -> Void
    private let queue = DispatchQueue(label: "com.rattamer.smoothscroll")
    private let queueKey = DispatchSpecificKey<Void>()
    private var timer: DispatchSourceTimer?

    /// Called on the coordinator's queue with one sample per raw wheel
    /// movement (`.raw`) and per posted value (`.output`), always before the
    /// corresponding `poster` call.
    public var onSample: ((ScrollSample) -> Void)?

    public init(smoother: ScrollSmoother,
                now: @escaping () -> Date = Date.init,
                poster: @escaping (Double) -> Void) {
        self.smoother = smoother
        self.now = now
        self.poster = poster
        queue.setSpecific(key: queueKey, value: ())
    }

    public func onWheelMovement(_ movement: WheelMovement) {
        queue.async { [weak self] in
            guard let self else { return }
            let now = self.now()
            if let onSample = self.onSample {
                onSample(ScrollSample(time: now, kind: .raw, value: self.smoother.rawPixels(for: movement)))
            }
            self.post(self.smoother.feed(movement, at: now))
            if self.smoother.hasPendingWork(at: now) {
                self.startTimerIfNeeded()
            }
        }
    }

    /// Applies a new parameter set live. Uses a soft reset: momentum and
    /// direction state are dropped so stale tuning does not leak over, but an
    /// in-flight glide keeps draining (`target`/`current`/`carry` survive),
    /// so changing presets mid-scroll does not kill the wheel.
    public func setParameters(_ parameters: ScrollSmoother.Parameters) {
        queue.async { [weak self] in
            guard let self else { return }
            self.smoother.parameters = parameters
            self.smoother.softReset()
        }
    }

    /// Marks the coordinator active. The tick timer is armed lazily on the
    /// first wheel movement with motion to emit.
    public func start() {
        Self.log.info("smooth scroll coordinator ready")
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.smoother.reset()
            Self.log.info("smooth scroll timer stopped")
        }
    }

    /// Runs a closure on the coordinator's serial queue and returns its result,
    /// keeping smoother access on the queue that owns it.
    func synchronized<T>(_ body: (ScrollSmoother) -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return body(smoother)
        }
        return queue.sync { body(smoother) }
    }

    /// Whether the tick timer is currently armed.
    var isTicking: Bool {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return timer != nil
        }
        return queue.sync { timer != nil }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.tickInterval,
                       repeating: Self.tickInterval,
                       leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = self.now()
            self.post(self.smoother.tick(at: now))
            if !self.smoother.hasPendingWork(at: now) {
                self.stopTimer()
            }
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    /// Emits the `.output` sample for a value (including 0, which the feed
    /// returns while smoothing accumulates) and then forwards it to the poster.
    private func post(_ value: Double) {
        if let onSample = onSample {
            onSample(ScrollSample(time: now(), kind: .output, value: value))
        }
        poster(value)
    }
}
