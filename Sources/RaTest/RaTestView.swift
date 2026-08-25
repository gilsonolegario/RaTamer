import AppKit
import RaTamerCore
import SwiftUI

struct RaTestView: View {
    let engine: RaTestEngine
    @State private var config: Config
    @State private var status = ""
    @State private var controls: [ControlInfo] = []
    @State private var pressed = Set<UInt16>()
    @State private var smoothEnabled = false
    @State private var maxBoost: Double = SmoothnessLevel.maxBoost(SmoothnessLevel.defaultValue)
    @State private var momentumDecay: Double = SmoothnessLevel.momentumDecay(SmoothnessLevel.defaultValue)
    @State private var momentumEnabled: Bool = SmoothnessLevel.momentumEnabled(SmoothnessLevel.defaultValue)
    @State private var pixelsPerNotch: Double = SmoothnessLevel.pixelsPerNotch(SmoothnessLevel.defaultValue)
    @State private var accelerationWindow: Double = ScrollSmoother.defaultAccelerationWindow
    @State private var feedGapTimeout: Double = ScrollSmoother.defaultFeedGapTimeout
    @State private var momentumStopThreshold: Double = ScrollSmoother.defaultMomentumStopThreshold
    @State private var bounceWindow: Double = ScrollSmoother.defaultBounceWindow
    @State private var bounceRatio: Double = ScrollSmoother.defaultBounceRatio
    @State private var bounceDamping: Double = ScrollSmoother.defaultBounceDamping
    @State private var reversalConfirmation: Int = ScrollSmoother.defaultReversalConfirmation
    @State private var directionThreshold: Double = ScrollSmoother.defaultDirectionThreshold
    @State private var smoothingEnabled: Bool = SmoothnessLevel.smoothingEnabled(SmoothnessLevel.defaultValue)
    @State private var smoothFraction: Double = SmoothnessLevel.smoothFraction(SmoothnessLevel.defaultValue)
    @State private var glideStopThreshold: Double = SmoothnessLevel.glideStopThreshold(SmoothnessLevel.defaultValue)
    @State private var syncedLevel: Double?
    @State private var selectedPreset: SmoothnessPreset = .native
    @State private var thumbWheelLog: [String] = []

    init(engine: RaTestEngine) {
        self.engine = engine
        _config = State(initialValue: engine.configStore.load())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Status
                if !status.isEmpty {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(Color.ratAccent)
                        .padding(.vertical, 4)
                }

                // Buttons
                RatCard {
                    SectionHeader(title: "Buttons")
                    VStack(spacing: 6) {
                        ForEach(controls, id: \.cid) { control in
                            row(for: control)
                        }
                    }
                    Text(footerText).font(.caption).foregroundStyle(.secondary)
                }

                // Smooth Scroll
                RatCard {
                    SectionHeader(title: "Smooth Scroll")
                    smoothPanel
                }

                // Wheel Mode
                RatCard {
                    SectionHeader(title: "Wheel Mode")
                    wheelModePanel
                }

                // DPI
                RatCard {
                    SectionHeader(title: "DPI")
                    dpiPanel
                }

                // Thumb Wheel
                RatCard {
                    SectionHeader(title: "Thumb Wheel")
                    thumbWheelPanel
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, idealWidth: 620, maxWidth: .infinity)
        .onAppear {
            engine.onStatus = { status = $0 }
            engine.onControlsChanged = { controls = $0 }
            engine.onPress = { cid in DispatchQueue.main.async { pressed.insert(cid) } }
            engine.onRelease = { cid in DispatchQueue.main.async { pressed.remove(cid) } }
            engine.onThumbWheel = { direction in
                DispatchQueue.main.async {
                    let label = direction == .left ? "left" : "right"
                    thumbWheelLog.append(label)
                    if thumbWheelLog.count > 20 { thumbWheelLog.removeFirst(thumbWheelLog.count - 20) }
                }
            }
            _ = engine.start()
        }
    }

    private func row(for control: ControlInfo) -> some View {
        HStack(alignment: .center) {
            Text(ControlTaskName.name(for: control.taskID))
                .frame(width: 170, alignment: .leading)
            Text(String(format: "0x%04X", control.cid))
                .font(.caption.monospaced())
                .frame(width: 50, alignment: .leading)
            Text(String(format: "tid 0x%04X", control.taskID))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            if control.isDivertable {
                Picker("", selection: actionBinding(for: control)) {
                    actionOptions
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                SegmentedPillRow(segments: [
                    ("Run", { engine.runAction(for: control.cid) }, !isDisabled(for: control))
                ])
                .fixedSize()
            } else {
                Text("Native only").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(pressed.contains(control.cid) ? Color.ratAccent.opacity(0.18) : Color.clear)
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
        ForEach(ActionCatalog.allActions, id: \.self) { action in
            Text(ActionCatalog.title(for: action)).tag(action)
        }
    }

    private var smoothPanel: some View {
        Group {
            Toggle("Enabled (diverts wheel to HID++)", isOn: $smoothEnabled)
                .onChange(of: smoothEnabled) { _, _ in applySmoothEnable() }
            Text("Multiplier: \(engine.wheelMultiplier ?? 8)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Level").frame(width: 160, alignment: .leading)
                Slider(value: levelBinding, in: 0...100, step: 1)
                Text(levelLabel).font(.caption.monospaced()).frame(width: 56, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text("Presets").frame(width: 160, alignment: .leading)
                SegmentedPillPicker(
                    items: SmoothnessPreset.allCases,
                    selection: $selectedPreset,
                    label: { $0.displayName }
                )
                .onChange(of: selectedPreset) { _, newPreset in
                    applyPreset(newPreset)
                }
            }
            sliderRow("Max boost", value: $maxBoost, range: 1.0...6.0, step: 0.1)
            sliderRow("Momentum decay", value: $momentumDecay, range: 0.5...0.98, step: 0.01)
            Toggle("Momentum", isOn: $momentumEnabled)
                .onChange(of: momentumEnabled) { _, _ in applySmoothParams() }
            Toggle("Smoothing (glide)", isOn: $smoothingEnabled)
                .onChange(of: smoothingEnabled) { _, _ in applySmoothParams() }
            sliderRow("Smooth fraction", value: $smoothFraction, range: 0.02...0.15, step: 0.01)
            sliderRow("Glide stop", value: $glideStopThreshold, range: 0.0...2.0, step: 0.1)
            sliderRow("Pixels per notch", value: $pixelsPerNotch, range: 1...200, step: 1)
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

    private var wheelModePanel: some View {
        Group {
            if engine.hasSmartShift {
                HStack {
                    Text("Mode: \(engine.wheelModeDescription)")
                        .frame(width: 200, alignment: .leading)
                    SegmentedPillRow(segments: [
                        ("Ratchet", { engine.setWheelMode(ratcheted: true) }, engine.wheelModeDescription == "Ratchet"),
                        ("Free-spin", { engine.setWheelMode(ratcheted: false) }, engine.wheelModeDescription != "Ratchet")
                    ])
                    .fixedSize()
                    Spacer()
                }
            } else {
                Text("Device has no SmartShift.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dpiPanel: some View {
        HStack {
            Text("Current: \(engine.currentDPI.map(String.init) ?? "—")")
                .frame(width: 200, alignment: .leading)
            Text("Cycle: \(engine.dpiCycleValues.map(String.init).joined(separator: " → "))")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
            SegmentedPillRow(segments: [
                ("Cycle DPI", { engine.cycleDPI() }, !engine.dpiCycleValues.isEmpty)
            ])
            Spacer()
        }
    }

    private var thumbWheelPanel: some View {
        HStack {
            Text(thumbWheelLog.isEmpty
                 ? "Spin the thumb wheel."
                 : "Notches: " + thumbWheelLog.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(thumbWheelLog.isEmpty ? .secondary : .primary)
            Spacer()
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).frame(width: 160, alignment: .leading)
            Slider(value: value, in: range, step: step) { editing in
                if !editing, syncedLevel != nil { syncedLevel = nil }
            }
            .onChange(of: value.wrappedValue) { _, _ in applySmoothParams() }
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var levelBinding: Binding<Double> {
        Binding(
            get: {
                if let syncedLevel { return syncedLevel }
                return SmoothnessLevel.defaultValue
            },
            set: { applyLevel($0) }
        )
    }

    private var levelLabel: String {
        if let syncedLevel { return String(format: "%.0f", syncedLevel) }
        return "custom"
    }

    private func applyPreset(_ preset: SmoothnessPreset) {
        if preset == .native {
            smoothEnabled = false
            return
        }
        applyLevel(preset.level)
    }

    private func applyLevel(_ level: Double) {
        syncedLevel = level
        let p = SmoothnessLevel.parameters(level: level,
                                           multiplier: engine.wheelMultiplier ?? 8,
                                           invert: false)
        maxBoost = p.maxBoost
        momentumDecay = p.momentumDecay
        momentumEnabled = p.momentumEnabled
        smoothingEnabled = p.smoothingEnabled
        pixelsPerNotch = p.pixelsPerNotch
        smoothFraction = p.smoothFraction
        glideStopThreshold = p.glideStopThreshold
        applySmoothParams()
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
            directionThreshold: directionThreshold,
            smoothingEnabled: smoothingEnabled,
            smoothFraction: smoothFraction,
            glideStopThreshold: glideStopThreshold)
    }

    private func applySmoothEnable() {
        engine.setSmoothScroll(enabled: smoothEnabled, parameters: currentParams)
    }

    private func applySmoothParams() {
        engine.setSmoothParameters(currentParams)
    }
}
