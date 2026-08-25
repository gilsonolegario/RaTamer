import Foundation

/// Thread-safe ring buffer of `ScrollSample`s. The HID++/smoothscroll queue
/// appends while the UI thread snapshots; the lock keeps both ordered and
/// race-free. Oldest samples fall off when the capacity is exceeded.
public final class ScrollSampleBuffer {
    private let lock = NSLock()
    private var samples: [ScrollSample]
    private let capacity: Int

    public init(capacity: Int = 900) {
        self.capacity = max(1, capacity)
        self.samples = []
    }

    public func append(_ sample: ScrollSample) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    /// Samples inside `[now - window, now]`, oldest first, capped at capacity.
    public func samples(in window: TimeInterval, before now: Date) -> [ScrollSample] {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = now.addingTimeInterval(-window)
        return samples
            .filter { $0.time >= cutoff && $0.time <= now }
            .sorted { $0.time < $1.time }
    }
}
