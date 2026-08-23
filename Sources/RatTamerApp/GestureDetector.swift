import AppKit
import RatTamerCore
import os

/// Accumulates raw XY deltas while the gesture control is held and fires the
/// dominant direction once it crosses the threshold. The firmware freezes the
/// OS cursor while the button is held and reroutes motion as HID++ rawXY
/// events, so `NSEvent.mouseLocation` cannot be used.
final class GestureDetector {
    private static let log = Logger(subsystem: "com.rattamer", category: "engine")
    private let actionEngine: ActionEngine
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var firedDirection: GestureDirection?
    private var config: GestureConfig?

    init(actionEngine: ActionEngine) {
        self.actionEngine = actionEngine
    }

    func begin(config: GestureConfig) {
        end()
        self.config = config
        accumulatedX = 0
        accumulatedY = 0
        firedDirection = nil
        Self.log.info("gesture begin")
    }

    func motion(dx: Int16, dy: Int16) {
        guard let config else { return }
        accumulatedX += CGFloat(dx)
        accumulatedY -= CGFloat(dy)
        guard let direction = GestureMath.direction(dx: accumulatedX,
                                                    dy: accumulatedY,
                                                    limit: GestureMath.defaultLimit) else {
            firedDirection = nil
            return
        }
        guard direction != firedDirection else { return }
        firedDirection = direction
        Self.log.info("gesture fire dir=\(String(describing: direction), privacy: .public) dx=\(String(format: "%.0f", self.accumulatedX), privacy: .public) dy=\(String(format: "%.0f", self.accumulatedY), privacy: .public)")
        let action: ButtonAction = switch direction {
        case .up: config.up
        case .down: config.down
        case .left: config.left
        case .right: config.right
        }
        do {
            try actionEngine.execute(action)
        } catch {
            Self.log.error("gesture execute failed: \(String(describing: error), privacy: .public)")
        }
    }

    func end() {
        guard let config else { return }
        if firedDirection == nil {
            Self.log.info("gesture end click dx=\(String(format: "%.0f", self.accumulatedX), privacy: .public) dy=\(String(format: "%.0f", self.accumulatedY), privacy: .public)")
            do {
                try actionEngine.execute(config.click)
            } catch {
                Self.log.error("gesture click execute failed: \(String(describing: error), privacy: .public)")
            }
        } else {
            Self.log.info("gesture end dir=\(String(describing: self.firedDirection), privacy: .public)")
        }
        self.config = nil
        accumulatedX = 0
        accumulatedY = 0
        firedDirection = nil
    }
}
