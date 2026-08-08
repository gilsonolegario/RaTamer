import Foundation

public enum ThumbWheel {
    public enum Direction: Equatable {
        case left
        case right
    }

    public static let notchThreshold: Int64 = 10

    public static func isThumbWheel(deltaX: Int64, deltaY: Int64, isContinuous: Int64, phase: Int64) -> Bool {
        deltaX != 0 && isContinuous == 0 && phase == 0
    }

    public static func direction(forDeltaX deltaX: Int64) -> Direction {
        deltaX > 0 ? .right : .left
    }

    public struct NotchAccumulator {
        private var pending: Int64 = 0

        public init() {}

        public mutating func push(pixels: Int64, direction: Direction) -> Int {
            guard pixels != 0 else { return 0 }
            let signed = direction == .right ? abs(pixels) : -abs(pixels)
            if pending != 0 && (pending > 0) != (signed > 0) {
                pending = 0
            }
            pending += signed
            var notches = 0
            while abs(pending) >= ThumbWheel.notchThreshold {
                pending -= (pending > 0 ? ThumbWheel.notchThreshold : -ThumbWheel.notchThreshold)
                notches += 1
            }
            return notches
        }

        public mutating func reset() {
            pending = 0
        }
    }
}
