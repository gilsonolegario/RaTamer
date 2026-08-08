import Foundation

public enum DPICycle {
    public static let defaultPresets: [UInt16] = [1000, 1600, 2000, 4000]

    public static func next(current: UInt16, presets: [UInt16]) -> UInt16? {
        guard !presets.isEmpty else { return nil }
        if let index = presets.firstIndex(of: current) {
            return presets[(index + 1) % presets.count]
        }
        return presets[0]
    }
}
