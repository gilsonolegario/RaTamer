import Foundation

/// One timestamped point of the live scroll waveform: either the raw wheel
/// input (`raw`) or the tamed output that was actually posted (`output`).
public struct ScrollSample: Equatable {
    public enum Kind {
        case raw
        case output
    }

    public let time: Date
    public let kind: Kind
    public let value: Double

    public init(time: Date, kind: Kind, value: Double) {
        self.time = time
        self.kind = kind
        self.value = value
    }
}