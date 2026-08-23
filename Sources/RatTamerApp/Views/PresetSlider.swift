import SwiftUI
import RatTamerCore

/// A native smoothness slider matching the other sliders in the app
/// (`.small`, accent tint, 22pt tall) with a reference strip below showing a
/// tick bar at each preset level. The active preset's bar is highlighted.
struct PresetSlider: View {
    @Binding var value: Double
    let currentLevel: Double?
    let onSelect: (SmoothnessPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: Binding(
                get: { value },
                set: { newValue in value = newValue.rounded() }
            ), in: SmoothnessLevel.min...SmoothnessLevel.max, step: 1)
            .controlSize(.small)
            .tint(Color.accentColor)
            .frame(height: 22)
            .frame(maxWidth: .infinity)

            presetReferenceBar

            presetChips
        }
    }

    /// Thin reference strip: a tick bar at each preset level, inset by the
    /// knob radius so the bars line up with the slider track. The active
    /// preset's bar is taller and accent-tinted.
    private var presetReferenceBar: some View {
        GeometryReader { geo in
            let span = SmoothnessLevel.max - SmoothnessLevel.min
            ZStack(alignment: .leading) {
                ForEach(SmoothnessPreset.allCases, id: \.self) { preset in
                    let x = geo.size.width * (preset.level - SmoothnessLevel.min) / span
                    Rectangle()
                        .fill(isActive(preset) ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: 3, height: isActive(preset) ? 12 : 8)
                        .position(x: x, y: geo.size.height / 2)
                }
            }
        }
        .frame(height: 12)
        .padding(.horizontal, 7)
    }

    private func isActive(_ preset: SmoothnessPreset) -> Bool {
        currentLevel == preset.level
    }

    private var presetChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 4)], spacing: 4) {
            ForEach(SmoothnessPreset.allCases, id: \.self) { preset in
                presetChip(for: preset)
            }
        }
    }

    private func presetChip(for preset: SmoothnessPreset) -> some View {
        let isActive = currentLevel == preset.level
        return Button(preset.displayName) { onSelect(preset) }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(isActive ? Color.accentColor : nil)
            .help(preset.displayName)
    }
}