import AppKit
import RatTamerCore
import SwiftUI

struct RatTestView: View {
    let engine: RatTestEngine
    @State private var config: Config
    @State private var status = ""
    @State private var controls: [ControlInfo] = []
    @State private var pressed = Set<UInt16>()
    @State private var smoothEnabled = false
    @State private var maxBoost: Double = SmoothnessLevel.maxBoost(SmoothnessLevel.defaultValue)
    @State private var momentumDecay: Double = SmoothnessLevel.momentumDecay(SmoothnessLevel.defaultValue)
    @State private var momentumEnabled: Bool = SmoothnessLevel.momentumEnabled(SmoothnessLevel.defaultValue)
    @State private var pixelsPerNotch: Double = ScrollSmoother.defaultPixelsPerNotch
    @State private var accelerationWindow: Double = ScrollSmoother.defaultAccelerationWindow
    @State private var feedGapTimeout: Double = ScrollSmoother.defaultFeedGapTimeout
    @State private var momentumStopThreshold: Double = ScrollSmoother.defaultMomentumStopThreshold
    @State private var bounceWindow: Double = ScrollSmoother.defaultBounceWindow
    @State private var bounceRatio: Double = ScrollSmoother.defaultBounceRatio
    @State private var bounceDamping: Double = ScrollSmoother.defaultBounceDamping
    @State private var reversalConfirmation: Int = ScrollSmoother.defaultReversalConfirmation
    @State private var directionThreshold: Double = ScrollSmoother.defaultDirectionThreshold

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
            Divider()
            Text("Smooth Scroll").font(.headline)
            smoothPanel
        }
        .padding()
        .frame(width: 660, height: 720)
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

    private var smoothPanel: some View {
        Group {
            Toggle("Enabled (diverts wheel to HID++)", isOn: $smoothEnabled)
                .onChange(of: smoothEnabled) { _, _ in applySmoothEnable() }
            Text("Multiplier: \(engine.wheelMultiplier ?? 8)")
                .font(.caption)
                .foregroundStyle(.secondary)
            sliderRow("Max boost", value: $maxBoost, range: 1.0...6.0, step: 0.1)
            sliderRow("Momentum decay", value: $momentumDecay, range: 0.5...0.98, step: 0.01)
            Toggle("Momentum", isOn: $momentumEnabled)
                .onChange(of: momentumEnabled) { _, _ in applySmoothParams() }
            sliderRow("Pixels per notch", value: $pixelsPerNotch, range: 1...40, step: 1)
            sliderRow("Accel window (s)", value: $accelerationWindow, range: 0.01...0.20, step: 0.01)
            sliderRow("Feed gap timeout (s)", value: $feedGapTimeout, range: 0.02...0.30, step: 0.01)
            sliderRow("Momentum stop", value: $momentumStopThreshold, range: 0.0...1.0, step: 0.05)
            sliderRow("Bounce window (s)", value: $bounceWindow, range: 0.0...0.20, step: 0.005)
            sliderRow("Bounce ratio", value: $bounceRatio, range: 0.1...1.0, step: 0.05)
            sliderRow("Bounce damping", value: $bounceDamping, range: 0.0...1.0, step: 0.05)
            Stepper("Reversal confirmation: \(reversalConfirmation)",
                    value: $reversalConfirmation, in: 1...5)
                .onChange(of: reversalConfirmation) { _, _ in applySmoothParams() }
            sliderRow("Direction threshold", value: $directionThreshold, range: 0.0...5.0, step: 0.25)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).frame(width: 160, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .onChange(of: value.wrappedValue) { _, _ in applySmoothParams() }
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var currentParams: ScrollSmoother.Parameters {
        ScrollSmoother.Parameters(
            multiplier: engine.wheelMultiplier ?? 8,
            momentumEnabled: momentumEnabled,
            invert: false,
            maxBoost: maxBoost,
            momentumDecay: momentumDecay,
            pixelsPerNotch: pixelsPerNotch,
            accelerationWindow: accelerationWindow,
            feedGapTimeout: feedGapTimeout,
            momentumStopThreshold: momentumStopThreshold,
            bounceWindow: bounceWindow,
            bounceRatio: bounceRatio,
            bounceDamping: bounceDamping,
            reversalConfirmation: reversalConfirmation,
            directionThreshold: directionThreshold)
    }

    private func applySmoothEnable() {
        engine.setSmoothScroll(enabled: smoothEnabled, parameters: currentParams)
    }

    private func applySmoothParams() {
        engine.setSmoothParameters(currentParams)
    }
}
