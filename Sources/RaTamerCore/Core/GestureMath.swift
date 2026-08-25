import CoreGraphics
import Foundation

public enum GestureDirection: Equatable {
    case up, down, left, right
}

public enum GestureMath {
    public static let defaultLimit: CGFloat = 40

    public static func direction(from start: CGPoint,
                                 to current: CGPoint,
                                 limit: CGFloat = defaultLimit) -> GestureDirection? {
        direction(dx: current.x - start.x, dy: current.y - start.y, limit: limit)
    }

    /// Classify accumulated raw deltas. `dx` positive = right; `dy` follows
    /// screen convention (positive = up). Returns nil while below `limit`.
    public static func direction(dx: CGFloat, dy: CGFloat,
                                 limit: CGFloat = defaultLimit) -> GestureDirection? {
        guard abs(dx) >= limit || abs(dy) >= limit else { return nil }
        if abs(dy) > abs(dx) {
            return dy > 0 ? .up : .down
        } else {
            return dx < 0 ? .left : .right
        }
    }
}
