import AppKit
import RaTamerCore
import SwiftUI

struct ButtonsTabView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var pressMonitor = AppModel.shared.pressMonitor
    @State private var shortcutControl: ControlInfo?
    @State private var gestureControl: ControlInfo?
    @State private var shortcutThumbSide: ThumbWheelSide?
    @State private var runShortcutControl: ControlInfo?
    @State private var runShortcutThumbSide: ThumbWheelSide?

    private var config: Config { model.config }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Button Mapping")
                        .font(.headline)
                    Text("Assign shortcuts, system actions, or gestures per control.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SegmentedPillRow(segments: [
                    (label: "Reload", action: {
                        model.reloadConfig()
                        model.engine?.applyConfig()
                    }, isHighlighted: false)
                ], compact: true)
            }

            RatSectionCard(title: "Thumb Wheel") {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Horizontal wheel notches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HelpButton(text: "Actions for horizontal scroll. If the direction feels inverted, swap Left and Right.")
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    thumbWheelRow(side: .left)
                    Divider().opacity(0.4)
                    thumbWheelRow(side: .right)
                }
            }

            RatSectionCard(title: "Hardware Controls") {
                if model.controls.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: model.isConnected ? "computermouse" : "cable.connector.slash")
                            .foregroundStyle(.secondary)
                        Text(model.isConnected
                             ? "No reprogrammable controls reported by this device."
                             : "Connect your mouse to view and remap hardware buttons.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !model.isConnected && !model.isReconnecting {
                            SegmentedPillRow(segments: [
                                (label: "Reconnect", action: { model.engine?.reconnect() }, isHighlighted: false)
                            ], compact: true)
                        }
                    }
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(model.controls.enumerated()), id: \.element.cid) { index, control in
                            if index > 0 {
                                Divider().opacity(0.35)
                            }
                            row(for: control)
                        }
                    }
                }
            }
        }
        .padding(16)
        .sheet(item: $shortcutControl) { control in
            ShortcutRecorderView { key, modifiers in
                setAction(.shortcut(key: key, modifiers: modifiers), for: control)
                shortcutControl = nil
            } onCancel: {
                shortcutControl = nil
            }
        }
        .sheet(item: $gestureControl) { control in
            GestureEditorView(initial: currentGestureConfig(for: control)) { gestureConfig in
                setAction(.gesture(gestureConfig), for: control)
                gestureControl = nil
            }
        }
        .sheet(item: $shortcutThumbSide) { side in
            ShortcutRecorderView { key, modifiers in
                setThumbWheelAction(.shortcut(key: key, modifiers: modifiers), side: side)
                shortcutThumbSide = nil
            } onCancel: {
                shortcutThumbSide = nil
            }
        }
        .sheet(item: $runShortcutControl) { control in
            RunShortcutView { name in
                setAction(.runShortcut(name), for: control)
                runShortcutControl = nil
            } onCancel: {
                runShortcutControl = nil
            }
        }
        .sheet(item: $runShortcutThumbSide) { side in
            RunShortcutView { name in
                setThumbWheelAction(.runShortcut(name), side: side)
                runShortcutThumbSide = nil
            } onCancel: {
                runShortcutThumbSide = nil
            }
        }
    }

    private func currentGestureConfig(for control: ControlInfo) -> GestureConfig {
        guard case .gesture(let g) = (config.action(forCID: control.cid) ?? .disabled) else {
            return .logitechDefault()
        }
        return g
    }

    private func isGestureControl(_ control: ControlInfo) -> Bool {
        control.cid == ControlCID.thumbGesture || control.taskID == 0x00A9
    }

    private func row(for control: ControlInfo) -> some View {
        let isVirtualGesture = control.taskID == ControlCID.virtualGesture
        let assignedAction = config.action(forCID: control.cid) ?? .disabled
        let isPressed = pressMonitor.pressed.contains(control.cid)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: icon(for: control))
                    .frame(width: 20)
                    .foregroundStyle(isPressed ? Color.accentColor : .secondary)
                Text(ControlTaskName.name(for: control.taskID))
                    .font(.body)
                Spacer()
                if control.cid == ControlCID.dpiButton {
                    actionMenu(for: control)
                } else if isVirtualGesture {
                    Text("Virtual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if control.isDivertable {
                    if case .gesture = assignedAction, isGestureControl(control) {
                        Button("Edit…") {
                            gestureControl = control
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    actionMenu(for: control)
                } else if isSwapControl(for: control) {
                    swapControl(for: control)
                } else {
                    Text("Native only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .gesture(let gesture) = assignedAction {
                Text(gestureSummary(gesture))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 30)
            }

            if let hint = nativeBackForwardHint(for: control) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 30)
            }
            if let hint = virtualGestureHint(for: control) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 30)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .opacity(isVirtualGesture ? 0.6 : 1)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPressed ? Color.accentColor.opacity(0.24) : Color.clear)
        )
        .animation(.easeOut(duration: 0.12), value: isPressed)
    }

    private func gestureSummary(_ g: GestureConfig) -> String {
        let parts: [(String, ButtonAction)] = [
            ("Click", g.click),
            ("↑", g.up),
            ("↓", g.down),
            ("←", g.left),
            ("→", g.right),
        ]
        let active = parts.filter { $0.1 != .disabled }
        guard !active.isEmpty else { return "No gesture directions configured" }
        return active.map { "\($0.0): \(ActionCatalog.title(for: $0.1))" }.joined(separator: " · ")
    }

    private func nativeBackForwardHint(for control: ControlInfo) -> String? {
        guard control.cid == ControlCID.back || control.cid == ControlCID.forward else { return nil }
        guard (config.action(forCID: control.cid) ?? .disabled) == .disabled else { return nil }
        return "On macOS the native button does not navigate without Logitech Options. Use Back/Forward (⌘[ / ⌘])."
    }

    private func virtualGestureHint(for control: ControlInfo) -> String? {
        guard control.taskID == ControlCID.virtualGesture else { return nil }
        return "Virtual control used by the mouse to report gesture navigation via the physical Thumb/Gesture button."
    }

    private func isSwapControl(for control: ControlInfo) -> Bool {
        control.cid == ControlCID.leftButton || control.cid == ControlCID.rightButton
    }

    private func swapControl(for control: ControlInfo) -> some View {
        if control.cid == ControlCID.leftButton {
            return AnyView(swapMenu(for: control))
        } else {
            return AnyView(Text(config.swapLeftRight ? "Swapped" : "Normal")
                .font(.caption)
                .foregroundStyle(.secondary))
        }
    }

    private func swapMenu(for control: ControlInfo) -> some View {
        let swap = config.swapLeftRight
        return Menu {
            Button {
                setSwap(false)
            } label: {
                if !swap {
                    Label("Normal", systemImage: "checkmark")
                } else {
                    Text("Normal")
                }
            }
            Button {
                setSwap(true)
            } label: {
                if swap {
                    Label("Swap Left & Right", systemImage: "checkmark")
                } else {
                    Text("Swap Left & Right")
                }
            }
        } label: {
            menuPillLabel(icon: swap ? "arrow.left.arrow.right" : nil,
                          title: swap ? "Swap" : "Normal",
                          isRemapped: swap)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func setSwap(_ value: Bool) {
        model.updateConfig { $0.swapLeftRight = value }
        model.engine?.applyConfig()
    }

    private func icon(for control: ControlInfo) -> String {
        switch control.taskID {
        case 0x0038: return "cursorarrow"
        case 0x0039: return "arrow.up.right"
        case 0x003A: return "circle.inset.filled"
        case 0x003C: return "arrow.backward.circle"
        case 0x003E: return "arrow.forward.circle"
        case 0x009D: return "scroll"
        case 0x00A9: return "hand.draw"
        case ControlCID.virtualGesture: return "wand.and.stars"
        default: return "computermouse"
        }
    }

    private func actionMenu(for control: ControlInfo) -> some View {
        let action = config.action(forCID: control.cid) ?? .disabled
        return actionMenu(action: action,
                          onSet: { setAction($0, for: control) },
                          onCustomShortcut: { shortcutControl = control },
                          onRunShortcut: { runShortcutControl = control },
                          extras: {
                              if isGestureControl(control) {
                                  Button {
                                      gestureControl = control
                                  } label: {
                                      Label("Gesture…", systemImage: "hand.draw")
                                  }
                              }
                          })
    }

    private func actionMenu(action: ButtonAction,
                            onSet: @escaping (ButtonAction) -> Void,
                            onCustomShortcut: @escaping () -> Void,
                            onRunShortcut: @escaping () -> Void,
                            @ViewBuilder extras: () -> some View) -> some View {
        let isRemapped = action != .disabled
        return Menu {
            commonActionSections(onSet: onSet)
            Divider()
            Button {
                onCustomShortcut()
            } label: {
                Label("Custom Shortcut…", systemImage: "keyboard")
            }
            Button {
                onRunShortcut()
            } label: {
                Label("Run Shortcut…", systemImage: "applescript")
            }
            extras()
        } label: {
            menuPillLabel(icon: ActionCatalog.icon(for: action),
                          title: ActionCatalog.title(for: action),
                          isRemapped: isRemapped)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func menuPillLabel(icon: String?, title: String, isRemapped: Bool) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(isRemapped ? Color.accentColor : .secondary)
            }
            Text(title)
                .font(.callout.weight(isRemapped ? .medium : .regular))
                .foregroundStyle(isRemapped ? .primary : .secondary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isRemapped ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isRemapped ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func commonActionSections(onSet: @escaping (ButtonAction) -> Void) -> some View {
        Section("None") {
            Button {
                onSet(.disabled)
            } label: {
                Label("Native (default)", systemImage: "circle.slash")
            }
        }
        Section("Desktop & System") {
            systemItem("missionControl", onSet)
            systemItem("appExpose", onSet)
            systemItem("showDesktop", onSet)
            systemItem("previousSpace", onSet)
            systemItem("nextSpace", onSet)
            systemItem("spotlight", onSet)
            systemItem("lockScreen", onSet)
        }
        Section("Navigation") {
            shortcutItem("Back", key: "[", modifiers: ["command"], onSet)
            shortcutItem("Forward", key: "]", modifiers: ["command"], onSet)
            shortcutItem("New Tab", key: "t", modifiers: ["command"], onSet)
            shortcutItem("Close Tab", key: "w", modifiers: ["command"], onSet)
            shortcutItem("New Window", key: "n", modifiers: ["command"], onSet)
        }
        Section("Editing") {
            shortcutItem("Copy", key: "c", modifiers: ["command"], onSet)
            shortcutItem("Paste", key: "v", modifiers: ["command"], onSet)
            shortcutItem("Undo", key: "z", modifiers: ["command"], onSet)
            shortcutItem("Select All", key: "a", modifiers: ["command"], onSet)
            shortcutItem("Find", key: "f", modifiers: ["command"], onSet)
        }
        Section("Volume") {
            systemItem("volumeUp", onSet)
            systemItem("volumeDown", onSet)
            systemItem("volumeUpSmall", onSet)
            systemItem("volumeDownSmall", onSet)
            systemItem("volumeMute", onSet)
        }
        Section("Screenshot") {
            shortcutItem("Full Screen", key: "3", modifiers: ["command", "shift"], onSet)
            shortcutItem("Selection", key: "4", modifiers: ["command", "shift"], onSet)
            shortcutItem("Recording", key: "5", modifiers: ["command", "shift"], onSet)
        }
        Section("Click") {
            clickItem(button: 3, onSet)
            clickItem(button: 4, onSet)
        }
        Section("Pointer") {
            Button {
                onSet(.cycleDPI)
            } label: {
                Label("Cycle DPI", systemImage: "speedometer")
            }
        }
    }

    private func systemItem(_ name: String, _ onSet: @escaping (ButtonAction) -> Void) -> some View {
        Button {
            onSet(.system(name))
        } label: {
            Label(ActionCatalog.systemTitle(name), systemImage: ActionCatalog.systemIcon(name))
        }
    }

    private func shortcutItem(_ title: String, key: String, modifiers: [String], _ onSet: @escaping (ButtonAction) -> Void) -> some View {
        Button {
            onSet(.shortcut(key: key, modifiers: modifiers))
        } label: {
            Label(title, systemImage: "keyboard")
        }
    }

    private func clickItem(button: UInt8, _ onSet: @escaping (ButtonAction) -> Void) -> some View {
        Button {
            onSet(.click(button: button))
        } label: {
            Label(button == 3 ? "Back Click" : "Forward Click",
                  systemImage: button == 3 ? "arrow.left.to.line" : "arrow.right.to.line")
        }
    }

    private func thumbWheelRow(side: ThumbWheelSide) -> some View {
        let action = config.thumbWheelAction(for: side) ?? .disabled
        return HStack(spacing: 10) {
            Image(systemName: side == .right ? "arrow.turn.up.right" : "arrow.turn.up.left")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(side == .right ? "Thumb Wheel Right" : "Thumb Wheel Left")
            Spacer()
            actionMenu(action: action,
                       onSet: { setThumbWheelAction($0, side: side) },
                       onCustomShortcut: { shortcutThumbSide = side },
                       onRunShortcut: { runShortcutThumbSide = side },
                       extras: { EmptyView() })
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
    }

    private func setThumbWheelAction(_ action: ButtonAction, side: ThumbWheelSide) {
        model.updateConfig { $0.setThumbWheelAction(action, for: side) }
        model.engine?.applyConfig()
    }

    private func setAction(_ action: ButtonAction, for control: ControlInfo) {
        model.updateConfig { $0.setAction(action, forCID: control.cid) }
        model.engine?.applyAction(action, forCID: control.cid)
    }
}

struct RunShortcutView: View {
    @State private var name = ""
    @FocusState private var isFocused: Bool
    var onSave: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run Shortcut").font(.headline)
            Text("Name of the shortcut to run, as shown in the Shortcuts app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Shortcut name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(submit)
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("OK") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            name = ""
            isFocused = true
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
    }
}

struct ShortcutRecorderView: View {
    @State private var keyName: String?
    @State private var modifiers: [String] = []
    @State private var unsupportedKey = false
    @State private var recorderMonitor: Any?
    var onSave: (String, [String]) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record Shortcut")
                .font(.headline)
            Text("Press any key combination with optional modifiers (⌘, ⌥, ⌃, ⇧).")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Text(displayText)
                    .font(.title2.monospaced().weight(.medium))
                    .foregroundStyle(keyName == nil ? .secondary : .primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(keyName != nil ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.1), lineWidth: 1)
                    )
                Spacer()
            }

            if unsupportedKey {
                Text("That key is not supported for shortcuts. Try a letter, number, function, or arrow key.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel") { onCancel() }
                if keyName != nil {
                    Button("Clear") {
                        keyName = nil
                        modifiers = []
                        unsupportedKey = false
                    }
                }
                Spacer()
                Button("OK") {
                    if let keyName {
                        onSave(keyName, modifiers)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keyName == nil)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                capture(event)
                return nil
            }
        }
        .onDisappear {
            if let recorderMonitor {
                NSEvent.removeMonitor(recorderMonitor)
            }
            recorderMonitor = nil
        }
    }

    private var displayText: String {
        guard let keyName else { return "Waiting for key…" }
        return ActionCatalog.shortcutDisplay(key: keyName, modifiers: modifiers)
    }

    private func capture(_ event: NSEvent) {
        let mods = event.modifierFlags
        var result: [String] = []
        if mods.contains(.control) { result.append("control") }
        if mods.contains(.option) { result.append("option") }
        if mods.contains(.shift) { result.append("shift") }
        if mods.contains(.command) { result.append("command") }
        if let mapped = ActionEngine.keyName(for: event.keyCode, characters: event.charactersIgnoringModifiers) {
            modifiers = result
            keyName = mapped
            unsupportedKey = false
        } else {
            unsupportedKey = true
        }
    }
}
