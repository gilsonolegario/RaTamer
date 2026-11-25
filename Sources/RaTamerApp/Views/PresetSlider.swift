import SwiftUI
import RaTamerCore

private extension Color {
    init(hex: UInt) {
        self = Color(red: Double((hex >> 16) & 0xff) / 255,
                     green: Double((hex >> 8) & 0xff) / 255,
                     blue: Double(hex & 0xff) / 255)
    }
}

/// The smoothness control: a native slider matching the other sliders in the
/// app (`.small`, accent tint, 22pt tall) with a compact native preset menu
/// below. When the level sits exactly on a preset, that preset is selected in
/// the menu; any manual drag shows "Custom".
struct PresetSlider: View {
    @Binding var value: Double
    let currentLevel: Double?
    let onSelect: (SmoothnessPreset) -> Void
    var onReset: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlueSlider(value: Binding(
                get: { value },
                set: { value = Self.glued($0) }
            ))

            presetRuler

            HStack(spacing: 8) {
                Text("Preset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: presetSelection) {
                    Text("Custom").tag(SmoothnessPreset?.none)
                    ForEach(SmoothnessPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(Optional(preset))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 112, alignment: .leading)
                .help(HelpTexts.preset)
                Spacer()
                SegmentedPillRow(segments: [
                    (label: "Reset", action: { onReset() }, isHighlighted: false)
                ], compact: true)
            }
        }
    }

    /// Thin position marks for each preset along the slider scale, inset by
    /// the knob radius (9pt for 18pt knob) so they line up with the track.
    private var presetRuler: some View {
        GeometryReader { geo in
            let span = SmoothnessLevel.max - SmoothnessLevel.min
            ZStack(alignment: .leading) {
                ForEach(SmoothnessPreset.allCases, id: \.self) { preset in
                    let x = geo.size.width * (preset.level - SmoothnessLevel.min) / span
                    let active = currentLevel == preset.level
                    ZStack {
                        Rectangle()
                            .fill(active ? Color.accentColor : Color.secondary.opacity(0.4))
                            .frame(width: active ? 2.5 : 1.5, height: active ? 9 : 5)
                    }
                    .frame(width: 12, height: 14)
                    .contentShape(Rectangle())
                    .position(x: x, y: geo.size.height / 2)
                    .onTapGesture {
                        onSelect(preset)
                    }
                    .help(preset.displayName)
                }
            }
        }
        .frame(height: 10)
        .padding(.horizontal, 9)
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

    /// The slider itself: adaptive track with accent progress fill,
    /// white thumb with a soft shadow that grows on hover/drag. Keyboard and
    /// VoiceOver users still get a native Slider via accessibilityRepresentation.
    private struct GlueSlider: View {
        @Binding var value: Double
        @State private var active = false

        private let knob: CGFloat = 18
        private var span: Double { SmoothnessLevel.max - SmoothnessLevel.min }

        var body: some View {
            GeometryReader { geo in
                let travel = max(1, geo.size.width - knob)
                let fraction = CGFloat(min(1, max(0, (value - SmoothnessLevel.min) / span)))
                let thumbOffset = travel * fraction
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: thumbOffset + knob / 2, height: 4)
                    Circle()
                        .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                        .frame(width: knob, height: knob)
                        .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.28), radius: 4, y: 1.5)
                        .scaleEffect(active ? 1.08 : 1)
                        .offset(x: thumbOffset)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    active = true
                    let frac = min(1, max(0, (g.location.x - knob / 2) / travel))
                    value = SmoothnessLevel.min + Double(frac) * span
                }.onEnded { _ in active = false })
            }
            .frame(height: 22)
            .onHover { active = $0 }
            .accessibilityRepresentation {
                Slider(value: $value, in: SmoothnessLevel.min...SmoothnessLevel.max, step: 1)
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
