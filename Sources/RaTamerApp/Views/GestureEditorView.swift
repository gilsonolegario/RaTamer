import RaTamerCore
import SwiftUI

struct GestureEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config: GestureConfig
    var onSave: (GestureConfig) -> Void

    init(initial: GestureConfig, onSave: @escaping (GestureConfig) -> Void) {
        self._config = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gesture Actions")
                    .font(.headline)
                Text("Hold the Gesture button and click or swipe in a direction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                directionRow("Click", icon: "hand.point.up", binding: $config.click)
                Divider().opacity(0.4)
                directionRow("Swipe Up", icon: "arrow.up", binding: $config.up)
                directionRow("Swipe Down", icon: "arrow.down", binding: $config.down)
                directionRow("Swipe Left", icon: "arrow.left", binding: $config.left)
                directionRow("Swipe Right", icon: "arrow.right", binding: $config.right)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
            )

            HStack {
                Button("Reset Defaults") {
                    config = .logitechDefault()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(config) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func directionRow(_ title: String, icon: String,
                              binding: Binding<ButtonAction>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout)
            Spacer()
            Picker(title, selection: binding) {
                ForEach(standardOptions(preserving: binding.wrappedValue), id: \.self) { option in
                    Text(ActionCatalog.title(for: option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 210, alignment: .trailing)
        }
    }

    private func standardOptions(preserving current: ButtonAction) -> [ButtonAction] {
        var options: [ButtonAction] = [
            .disabled,
            .system("missionControl"),
            .system("appExpose"),
            .system("showDesktop"),
            .system("previousSpace"),
            .system("nextSpace"),
            .system("spotlight"),
            .system("lockScreen"),
            .system("volumeUp"),
            .system("volumeDown"),
            .system("volumeUpSmall"),
            .system("volumeDownSmall"),
            .system("volumeMute"),
            .shortcut(key: "[", modifiers: ["command"]),
            .shortcut(key: "]", modifiers: ["command"]),
            .shortcut(key: "t", modifiers: ["command"]),
            .shortcut(key: "w", modifiers: ["command"]),
            .click(button: 3),
            .click(button: 4),
            .cycleDPI,
        ]
        if !options.contains(current) {
            options.insert(current, at: 1)
        }
        return options
    }
}
