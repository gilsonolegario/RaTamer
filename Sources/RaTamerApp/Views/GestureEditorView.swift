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
        VStack(spacing: 16) {
            Text("Gesture").font(.headline)
            directionPicker("Click", icon: "hand.point.up", binding: $config.click)
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    directionPicker("↑", icon: "arrow.up", binding: $config.up)
                    HStack(spacing: 20) {
                        directionPicker("←", icon: "arrow.left", binding: $config.left)
                        directionPicker("→", icon: "arrow.right", binding: $config.right)
                    }
                    directionPicker("↓", icon: "arrow.down", binding: $config.down)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("OK") { onSave(config) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func directionPicker(_ title: String, icon: String,
                                 binding: Binding<ButtonAction>) -> some View {
        Picker(title, selection: binding) {
            Text("Native (default)").tag(ButtonAction.disabled)
            Text("Mission Control").tag(ButtonAction.system("missionControl"))
            Text("App Expose").tag(ButtonAction.system("appExpose"))
            Text("Show Desktop").tag(ButtonAction.system("showDesktop"))
            Text("Launchpad").tag(ButtonAction.system("launchpad"))
            Text("Previous Space").tag(ButtonAction.system("previousSpace"))
            Text("Next Space").tag(ButtonAction.system("nextSpace"))
            Text("Spotlight").tag(ButtonAction.system("spotlight"))
            Text("Lock Screen").tag(ButtonAction.system("lockScreen"))
            Text("Volume Up").tag(ButtonAction.system("volumeUp"))
            Text("Volume Down").tag(ButtonAction.system("volumeDown"))
            Text("Mute").tag(ButtonAction.system("volumeMute"))
            Text("Back (⌘[)").tag(ButtonAction.shortcut(key: "[", modifiers: ["command"]))
            Text("Forward (⌘])").tag(ButtonAction.shortcut(key: "]", modifiers: ["command"]))
            Text("Close Tab (⌘W)").tag(ButtonAction.shortcut(key: "w", modifiers: ["command"]))
        }
        .pickerStyle(.menu)
        .frame(width: 220)
    }
}
