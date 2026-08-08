import AppKit
import RatTamerCore
import SwiftUI

struct RatTestView: View {
    let engine: RatTestEngine
    @State private var config: Config
    @State private var status = ""
    @State private var controls: [ControlInfo] = []
    @State private var pressed = Set<UInt16>()

    init(engine: RatTestEngine) {
        self.engine = engine
        _config = State(initialValue: engine.configStore.load())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(status).font(.subheadline)
            Divider()
            Text("Buttons").font(.headline)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(controls, id: \.cid) { control in
                        row(for: control)
                    }
                }
            }
            Text(footerText).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 660, height: 500)
        .onAppear {
            engine.onStatus = { status = $0 }
            engine.onControlsChanged = { controls = $0 }
            engine.onPress = { cid in DispatchQueue.main.async { pressed.insert(cid) } }
            engine.onRelease = { cid in DispatchQueue.main.async { pressed.remove(cid) } }
            _ = engine.start()
        }
    }

    private func row(for control: ControlInfo) -> some View {
        HStack {
            Text(ControlTaskName.name(for: control.taskID))
                .frame(width: 190, alignment: .leading)
            Text(String(format: "0x%04X", control.cid))
                .font(.caption.monospaced())
                .frame(width: 52, alignment: .leading)
            Text(String(format: "tid 0x%04X", control.taskID))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            if control.isDivertable {
                Picker("", selection: actionBinding(for: control)) {
                    actionOptions
                }
                .pickerStyle(.menu)
                .frame(width: 190)
                Button("Run", action: { engine.runAction(for: control.cid) })
                    .disabled(isDisabled(for: control))
            } else {
                Text("Native only").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(4)
        .background(pressed.contains(control.cid) ? Color.accentColor.opacity(0.35) : Color.clear)
        .cornerRadius(4)
    }

    private func actionBinding(for control: ControlInfo) -> Binding<ButtonAction> {
        Binding(
            get: { config.action(forCID: control.cid) ?? .disabled },
            set: { newValue in
                config.setAction(newValue, forCID: control.cid)
                try? engine.configStore.save(config)
            }
        )
    }

    private func isDisabled(for control: ControlInfo) -> Bool {
        let action = config.action(forCID: control.cid)
        return action == nil || action == .disabled
    }

    private var footerText: String {
        if pressed.isEmpty {
            return "Press a physical button to identify it."
        }
        let names = pressed.map { cid -> String in
            let info = controls.first { $0.cid == cid }
            let name = info.map { ControlTaskName.name(for: $0.taskID) } ?? String(format: "0x%04X", cid)
            return "\(name) (0x\(String(format: "%04X", cid)))"
        }.sorted()
        return "Pressed: " + names.joined(separator: ", ")
    }

    private var actionOptions: some View {
        Group {
            Text("Disabled (native)").tag(ButtonAction.disabled)
            Text("Cmd+W (Close)").tag(ButtonAction.shortcut(key: "w", modifiers: ["command"]))
            Text("Volume Up").tag(ButtonAction.system("volumeUp"))
            Text("Volume Down").tag(ButtonAction.system("volumeDown"))
            Text("Mission Control").tag(ButtonAction.system("missionControl"))
            Text("Show Desktop").tag(ButtonAction.system("showDesktop"))
            Text("Previous Space").tag(ButtonAction.system("previousSpace"))
            Text("Next Space").tag(ButtonAction.system("nextSpace"))
            Text("Forward Click").tag(ButtonAction.click(button: 3))
            Text("Back Click").tag(ButtonAction.click(button: 4))
        }
    }
}
