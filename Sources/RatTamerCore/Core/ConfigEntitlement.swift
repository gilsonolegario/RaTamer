import Foundation

public extension Config {
    /// Returns a copy with pro features stripped unless the caller is entitled.
    /// Pure — never mutates the receiver or the stored config.
    func filteringProFeatures(entitled: (ProFeature) -> Bool) -> Config {
        var filtered = self

        func stripGesture(_ action: ButtonAction) -> ButtonAction {
            if case .gesture = action { return .disabled }
            return action
        }
        func stripRunShortcut(_ action: ButtonAction) -> ButtonAction {
            if case .runShortcut = action { return .disabled }
            return action
        }

        if !entitled(.gestures) {
            filtered.buttons = filtered.buttons.mapValues(stripGesture)
            if let left = filtered.thumbWheelLeft, case .gesture = left { filtered.thumbWheelLeft = nil }
            if let right = filtered.thumbWheelRight, case .gesture = right { filtered.thumbWheelRight = nil }
        }
        if !entitled(.runShortcut) {
            filtered.buttons = filtered.buttons.mapValues(stripRunShortcut)
            if let left = filtered.thumbWheelLeft, case .runShortcut = left { filtered.thumbWheelLeft = nil }
            if let right = filtered.thumbWheelRight, case .runShortcut = right { filtered.thumbWheelRight = nil }
        }
        if !entitled(.smartShift) {
            filtered.smartShiftMode = nil
            filtered.smartShiftSensitivity = nil
        }
        if !entitled(.smoothScroll) {
            filtered.smoothScrollEnabled = nil
            filtered.smoothScrollLevel = nil
        }
        return filtered
    }
}
