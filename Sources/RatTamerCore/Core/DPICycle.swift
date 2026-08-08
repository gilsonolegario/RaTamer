import Foundation

public enum DPICycle {
    public static let defaultPresets: [UInt16] = [1000, 1600, 2000, 4000]

    public static func recommendedPresets(from validList: [UInt16], limit: Int = 4) -> [UInt16] {
        guard !validList.isEmpty else { return defaultPresets }
        let values = Array(Set(validList)).sorted()
        guard values.count > limit else { return values }
        let count = max(2, min(limit, values.count))
        var chosen: [UInt16] = []
        for i in 0..<count {
            let index = Int((Double(i) / Double(count - 1) * Double(values.count - 1)).rounded())
            chosen.append(values[index])
        }
        return Array(Set(chosen)).sorted()
    }

    public static func next(current: UInt16, presets: [UInt16]) -> UInt16? {
        guard !presets.isEmpty else { return nil }
        if let index = presets.firstIndex(of: current) {
            return presets[(index + 1) % presets.count]
        }
        return presets[0]
    }
}
