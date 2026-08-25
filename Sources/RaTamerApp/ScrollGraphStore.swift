import Foundation
import RaTamerCore

/// Holds the live scroll samples produced by the smooth-scroll coordinator
/// and publishes a 5-second snapshot to the UI at 30 Hz. The timer only runs
/// while the graph window is open, so a closed window adds no wakeups.
final class ScrollGraphStore: ObservableObject {
    @Published private(set) var samples: [ScrollSample] = []

    /// Whether smooth scrolling is on. Refreshed by `ScrollGraphWindow` at a
    /// light 1 Hz poll while the window is open, so the empty-state warning
    /// reacts to toggles without re-reading the config file every frame.
    @Published var smoothEnabled = false

    private let buffer = ScrollSampleBuffer(capacity: 900)
    private let window: TimeInterval = 5
    private var timer: DispatchSourceTimer?

    func add(_ sample: ScrollSample) {
        buffer.append(sample)
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0 / 30.0,
                       repeating: 1.0 / 30.0,
                       leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in
            self?.flush()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func flush() {
        samples = buffer.samples(in: window, before: Date())
    }
}
