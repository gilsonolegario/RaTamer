import Foundation
import os

/// Owns the ~120 Hz scroll timer, feeds the pure `ScrollSmoother` with wheel
/// movements, and posts the resulting deltas via the injected poster closure.
/// All smoother access happens on this coordinator's private queue so the
/// HID++ loop thread and the timer never race on the smoother's state.
public final class ScrollSmootherCoordinator {
    private static let log = Logger(subsystem: "com.rattamer", category: "smoothscroll")
    private static let tickInterval: TimeInterval = 1.0 / 120.0

    private let smoother: ScrollSmoother
    private let now: () -> Date
    private let poster: (Double) -> Void
    private let queue = DispatchQueue(label: "com.rattamer.smoothscroll")
    private var timer: DispatchSourceTimer?

    public init(smoother: ScrollSmoother,
                now: @escaping () -> Date = Date.init,
                poster: @escaping (Double) -> Void) {
        self.smoother = smoother
        self.now = now
        self.poster = poster
    }

    public func onWheelMovement(_ movement: WheelMovement) {
        queue.async { [weak self] in
            guard let self else { return }
            self.poster(self.smoother.feed(movement, at: self.now()))
        }
    }

    /// Applies a new parameter set live, resetting the smoother so stale
    /// direction/momentum state from the previous tuning does not leak over.
    public func setParameters(_ parameters: ScrollSmoother.Parameters) {
        queue.async { [weak self] in
            guard let self else { return }
            self.smoother.parameters = parameters
            self.smoother.reset()
        }
    }

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.tickInterval,
                       repeating: Self.tickInterval,
                       leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.poster(self.smoother.tick(at: self.now()))
        }
        timer.resume()
        self.timer = timer
        Self.log.info("smooth scroll timer started")
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in
            self?.smoother.reset()
        }
        Self.log.info("smooth scroll timer stopped")
    }
}
