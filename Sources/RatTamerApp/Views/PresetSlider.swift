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
                set: { newValue in value = newValue.rounded() }
            ), in: SmoothnessLevel.min...SmoothnessLevel.max, step: 1)
            .controlSize(.small)
            .tint(Color.accentColor)
            .frame(height: 22)
            .frame(maxWidth: .infinity)

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

    /// The active preset when `currentLevel` lands exactly on one, otherwise
    /// nil ("Custom"). Choosing a preset forwards to `onSelect`.
    private var presetSelection: Binding<SmoothnessPreset?> {
        Binding(
            get: { SmoothnessPreset.allCases.first { $0.level == currentLevel } },
            set: { if let preset = $0 { onSelect(preset) } }
        )
    }
}
