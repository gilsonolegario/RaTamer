import SwiftUI
import RatTamerCore

/// The smoothness control: a native slider matching the other sliders in the
/// app (`.small`, accent tint, 22pt tall) with a compact native preset menu
/// below. When the level sits exactly on a preset, that preset is selected in
/// the menu; any manual drag shows "Custom".
struct PresetSlider: View {
    @Binding var value: Double
    let currentLevel: Double?
    let onSelect: (SmoothnessPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: Binding(
                get: { value },
                set: { value = Self.glued($0) }
            ), in: SmoothnessLevel.min...SmoothnessLevel.max, step: 1)
            .controlSize(.small)
            .tint(Color.accentColor)
            .frame(height: 22)
            .frame(maxWidth: .infinity)

            presetRuler

            HStack(spacing: 6) {
                Text("Preset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: presetSelection) {
                    Text("Custom").tag(SmoothnessPreset?.none)
                    ForEach(SmoothnessPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(Optional(preset))
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 120, alignment: .leading)
                Spacer()
            }
        }
    }

    /// Thin position marks for each preset along the slider scale, inset by
    /// the knob radius so they line up with the track. The active preset's
    /// mark is taller and accent-tinted; hovering shows the preset name.
    private var presetRuler: some View {
        GeometryReader { geo in
            let span = SmoothnessLevel.max - SmoothnessLevel.min
            ZStack(alignment: .leading) {
                ForEach(SmoothnessPreset.allCases, id: \.self) { preset in
                    let x = geo.size.width * (preset.level - SmoothnessLevel.min) / span
                    let active = currentLevel == preset.level
                    Rectangle()
                        .fill(active ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: active ? 2.5 : 1.5, height: active ? 8 : 5)
                        .position(x: x, y: geo.size.height / 2)
                        .help(preset.displayName)
                }
            }
        }
        .frame(height: 8)
        .padding(.horizontal, 7)
    }

    /// Magnetic glue: while dragging, values within ±2 of a preset stick to
    /// it (nearest wins), so the dense 80–90 preset cluster is easy to hit.
    static func glued(_ raw: Double) -> Double {
        let rounded = raw.rounded()
        let nearest = SmoothnessPreset.allCases
            .min(by: { abs($0.level - rounded) < abs($1.level - rounded) })
        guard let nearest, abs(nearest.level - rounded) <= 2 else { return rounded }
        return nearest.level
    }

    /// The active preset when `currentLevel` lands exactly on one, otherwise
    /// nil ("Custom"). Choosing a preset forwards to `onSelect`.
    private var presetSelection: Binding<SmoothnessPreset?> {
        Binding(
            get: { SmoothnessPreset.allCases.first { $0.level == currentLevel } },
            set: { if let preset = $0 { onSelect(preset) } }
        )
    }
}
