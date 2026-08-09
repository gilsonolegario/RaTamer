import AppKit
import RatTamerCore
import SwiftUI

struct ButtonsTabView: View {
    @ObservedObject private var model = AppModel.shared
    @State private var config = AppModel.shared.configStore.load()
    @State private var shortcutControl: ControlInfo?
    @State private var gestureControl: ControlInfo?
    @State private var shortcutThumbSide: ThumbWheelSide?
    @State private var runShortcutControl: ControlInfo?
    @State private var runShortcutThumbSide: ThumbWheelSide?
    @State private var smartShiftSensitivity: Double = 16
    @State private var showProAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Buttons").font(.headline)
            ScrollView {
                VStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Thumb Wheel")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        thumbWheelRow(side: .left)
                        thumbWheelRow(side: .right)
                        Text("Actions for horizontal scroll. If the direction feels inverted, swap Left/Right.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 44)
                        Divider().padding(.vertical, 4)
                    }
                    ForEach(model.controls, id: \.cid) { control in
                        row(for: control)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button("Reload") {
                    config = AppModel.shared.configStore.load()
                    smartShiftSensitivity = Double(config.smartShiftSensitivity ?? 16)
                    AppModel.shared.engine?.applyConfig()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
        }
        .padding()
        .onAppear {
            config = AppModel.shared.configStore.load()
            smartShiftSensitivity = Double(config.smartShiftSensitivity ?? 16)
        }
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
        .alert("RatTamer Pro", isPresented: $showProAlert) {
            Button("Get RatTamer Pro") {
                NSWorkspace.shared.open(ProStore.productURL)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Gestures, SmartShift, Run Shortcut and multiple profiles are Pro features.")
        }
    }

    private func currentGestureConfig(for control: ControlInfo) -> GestureConfig {
        guard case .gesture(let g) = (config.action(forCID: control.cid) ?? .disabled) else {
            return .logitechDefault()
        }
        return g
    }

    private func isPro(_ feature: ProFeature) -> Bool {
        AppModel.shared.isPro(feature)
    }

    private func proGate(_ feature: ProFeature, _ action: @escaping () -> Void) {
        guard isPro(feature) else {
            showProAlert = true
            return
        }
        action()
    }

    private var lockIcon: some View {
        Image(systemName: "lock.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func row(for control: ControlInfo) -> some View {
        let isVirtualGesture = control.taskID == 0x00B4
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Image(systemName: icon(for: control))
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                Text(ControlTaskName.name(for: control.taskID))
                    .frame(width: 170, alignment: .leading)
                Spacer()
                if control.cid == 0x00C4 {
                    HStack(spacing: 6) {
                        smartShiftMenu(for: control)
                        actionMenu(for: control)
                    }
                } else if isVirtualGesture {
                    Text("Virtual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if control.isDivertable {
                    actionMenu(for: control)
                } else if isSwapControl(for: control) {
                    swapControl(for: control)
                } else {
                    Text("Native only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let hint = nativeBackForwardHint(for: control) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 44)
            }
            if let hint = smartShiftHint(for: control) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 44)
            }
            if control.cid == 0x00C4, config.smartShiftMode == .smartshift {
                smartShiftSensitivityRow()
            }
            if let hint = virtualGestureHint(for: control) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .opacity(isVirtualGesture ? 0.55 : 1)
        .background(model.pressed.contains(control.cid)
                    ? Color.accentColor.opacity(0.35)
                    : Color.clear)
        .cornerRadius(6)
    }

    private func nativeBackForwardHint(for control: ControlInfo) -> String? {
        guard control.cid == 0x0053 || control.cid == 0x0056 else { return nil }
        guard (config.action(forCID: control.cid) ?? .disabled) == .disabled else { return nil }
        return "On macOS the native button does not navigate without Logitech Options. Use Back/Forward (⌘[ / ⌘])."
    }

    private func smartShiftHint(for control: ControlInfo) -> String? {
        guard control.cid == 0x00C4 else { return nil }
        return "Left: scroll wheel mode · Right: remap the button to another function."
    }

    private func virtualGestureHint(for control: ControlInfo) -> String? {
        guard control.taskID == 0x00B4 else { return nil }
        return "A virtual control the mouse uses to report gesture navigation. Gesture is triggered with the physical Thumb/Gesture button."
    }

    private func isSwapControl(for control: ControlInfo) -> Bool {
        control.cid == 0x0050 || control.cid == 0x0051
    }

    private func swapControl(for control: ControlInfo) -> some View {
        if control.cid == 0x0050 {
            return AnyView(swapMenu(for: control))
        } else {
            return AnyView(Text(config.swapLeftRight ? "Swap" : "Normal")
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
            HStack(spacing: 6) {
                Text(swap ? "Swap" : "Normal")
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func setSwap(_ value: Bool) {
        config.swapLeftRight = value
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func smartShiftMenu(for control: ControlInfo) -> some View {
        let mode = config.smartShiftMode
        return Menu {
            Button {
                proGate(.smartShift) { setSmartShiftMode(nil) }
            } label: {
                Label("Native (default)", systemImage: "arrow.uturn.left.circle")
                if mode == nil {
                    Image(systemName: "checkmark")
                }
            }
            Divider()
            Button {
                proGate(.smartShift) { setSmartShiftMode(.freespin) }
            } label: {
                Label("Free-spin", systemImage: "wind")
                if mode == .freespin {
                    Image(systemName: "checkmark")
                }
            }
            Button {
                proGate(.smartShift) { setSmartShiftMode(.ratcheted) }
            } label: {
                Label("Ratcheted", systemImage: "digitalcrown.arrow.clockwise")
                if mode == .ratcheted {
                    Image(systemName: "checkmark")
                }
            }
            if model.capabilities.hasSmartShift {
                Button {
                    proGate(.smartShift) { setSmartShiftMode(.smartshift) }
                } label: {
                    Label("SmartShift (auto)", systemImage: "bolt.badge.automatic")
                    if mode == .smartshift {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: smartShiftIcon(mode))
                Text(smartShiftTitle(mode))
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func smartShiftIcon(_ mode: SmartShiftMode?) -> String {
        switch mode {
        case .none: return "arrow.uturn.left.circle"
        case .freespin: return "wind"
        case .ratcheted: return "digitalcrown.arrow.clockwise"
        case .smartshift: return "bolt.badge.automatic"
        }
    }

    private func smartShiftSensitivityRow() -> some View {
        HStack(spacing: 8) {
            Text("Sensitivity")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Slider(value: $smartShiftSensitivity, in: 1...100, step: 1) { editing in
                if !editing {
                    setSmartShiftSensitivity(Int(smartShiftSensitivity))
                }
            }
            Text("\(Int(smartShiftSensitivity))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.leading, 44)
    }

    private func setSmartShiftSensitivity(_ value: Int) {
        config.smartShiftSensitivity = value
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func smartShiftTitle(_ mode: SmartShiftMode?) -> String {
        switch mode {
        case .none: return "Native"
        case .freespin: return "Free-spin"
        case .ratcheted: return "Ratcheted"
        case .smartshift: return "SmartShift"
        }
    }

    private func setSmartShiftMode(_ mode: SmartShiftMode?) {
        config.smartShiftMode = mode
        if mode == .smartshift {
            smartShiftSensitivity = Double(config.smartShiftSensitivity ?? 16)
        }
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func icon(for control: ControlInfo) -> String {
        switch control.taskID {
        case 0x0038: return "cursorarrow"
        case 0x0039: return "arrow.up.right"
        case 0x003A: return "circle.fill"
        case 0x003C: return "arrow.left.to.line"
        case 0x003E: return "arrow.right.to.line"
        case 0x009D: return "scroll"
        case 0x00A9: return "hand.draw"
        case 0x00B4: return "wand.and.stars"
        default: return "questionmark.circle"
        }
    }

    private func actionMenu(for control: ControlInfo) -> some View {
        let action = config.action(forCID: control.cid) ?? .disabled
        return actionMenu(title: ActionCatalog.title(for: action),
                          icon: ActionCatalog.icon(for: action),
                          onSet: { setAction($0, for: control) },
                          onCustomShortcut: { shortcutControl = control },
                          onRunShortcut: { runShortcutControl = control },
                          extras: {
                              if control.cid == 0x00C3 {
                                  Button {
                                      proGate(.gestures) { gestureControl = control }
                                  } label: {
                                      HStack {
                                          Label("Gesture…", systemImage: "hand.draw")
                                          if !isPro(.gestures) { lockIcon }
                                      }
                                  }
                              }
                          })
    }

    private func actionMenu(title: String, icon: String,
                            onSet: @escaping (ButtonAction) -> Void,
                            onCustomShortcut: @escaping () -> Void,
                            onRunShortcut: @escaping () -> Void,
                            @ViewBuilder extras: () -> some View) -> some View {
        Menu {
            commonActionSections(onSet: onSet)
            Divider()
            Button {
                onCustomShortcut()
            } label: {
                Label("Custom Shortcut…", systemImage: "keyboard")
            }
            Button {
                proGate(.runShortcut) { onRunShortcut() }
            } label: {
                HStack {
                    Label("Run Shortcut…", systemImage: "applescript")
                    if !isPro(.runShortcut) { lockIcon }
                }
            }
            extras()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
            systemItem("launchpad", onSet)
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
            Label(button == 3 ? "Back Click" : "Forward Click", systemImage: "hand.point.up")
        }
    }

    private func thumbWheelRow(side: ThumbWheelSide) -> some View {
        let action = config.thumbWheelAction(for: side) ?? .disabled
        return HStack(spacing: 12) {
            Image(systemName: side == .right ? "arrow.right.to.line" : "arrow.left.to.line")
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(side == .right ? "Thumb Wheel Right" : "Thumb Wheel Left")
                .frame(width: 170, alignment: .leading)
            Spacer()
            actionMenu(title: ActionCatalog.title(for: action),
                       icon: ActionCatalog.icon(for: action),
                       onSet: { setThumbWheelAction($0, side: side) },
                       onCustomShortcut: { shortcutThumbSide = side },
                       onRunShortcut: { runShortcutThumbSide = side },
                       extras: { EmptyView() })
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private func setThumbWheelAction(_ action: ButtonAction, side: ThumbWheelSide) {
        config.setThumbWheelAction(action, for: side)
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func setAction(_ action: ButtonAction, for control: ControlInfo) {
        config.setAction(action, forCID: control.cid)
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyAction(action, forCID: control.cid)
    }
}

struct RunShortcutView: View {
    @State private var name = ""
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
                .onSubmit(submit)
            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("OK") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            name = ""
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
    @State private var recorderMonitor: Any?
    var onSave: (String, [String]) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Press the key combination…")
                .font(.headline)
            Text(displayText)
                .font(.title2.monospaced())
                .frame(minWidth: 140)
                .padding()
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15)))
            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("OK") {
                    if let keyName {
                        onSave(keyName, modifiers)
                    }
                }
                .disabled(keyName == nil)
            }
        }
        .padding()
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
        }
    }

    private var displayText: String {
        guard let keyName else { return "…" }
        return ActionCatalog.shortcutDisplay(key: keyName, modifiers: modifiers)
    }

    private func capture(_ event: NSEvent) {
        let mods = event.modifierFlags
        var result: [String] = []
        if mods.contains(.control) { result.append("control") }
        if mods.contains(.option) { result.append("option") }
        if mods.contains(.shift) { result.append("shift") }
        if mods.contains(.command) { result.append("command") }
        modifiers = result
        keyName = ActionEngine.keyName(for: event.keyCode, characters: event.charactersIgnoringModifiers)
    }
}
