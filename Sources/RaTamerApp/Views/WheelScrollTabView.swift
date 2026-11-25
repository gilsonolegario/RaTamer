import AppKit
import RaTamerCore
import SwiftUI

/// Wheel & Scrolling — single home for every setting that changes how the
/// wheel feels: direction, SmartShift wheel mode and smooth-scroll tuning.
/// Absorbs the old Advanced tab (smooth-scroll physics) plus SmartShift
/// (formerly hanging off the DPI button in Buttons) and the direction
/// toggle (formerly in General).
struct WheelScrollTabView: View {
    @ObservedObject private var model = AppModel.shared

    // Smooth scroll state. Single source of truth — General no longer
    // duplicates the toggle/slider.
    @State private var enabled = false
    @State private var level: Double?
    @State private var maxBoost = ScrollSmoother.defaultMaxBoost
    @State private var momentumDecay = ScrollSmoother.defaultMomentumDecay
    @State private var momentumEnabled = false
    @State private var pixelsPerNotch = ScrollSmoother.defaultPixelsPerNotch
    @State private var accelerationWindow = ScrollSmoother.defaultAccelerationWindow
    @State private var feedGapTimeout = ScrollSmoother.defaultFeedGapTimeout
    @State private var momentumStopThreshold = ScrollSmoother.defaultMomentumStopThreshold
    @State private var bounceWindow = ScrollSmoother.defaultBounceWindow
    @State private var bounceRatio = ScrollSmoother.defaultBounceRatio
    @State private var bounceDamping = ScrollSmoother.defaultBounceDamping
    @State private var reversalConfirmation = ScrollSmoother.defaultReversalConfirmation
    @State private var directionThreshold = ScrollSmoother.defaultDirectionThreshold
    @State private var smoothingEnabled = false
    @State private var smoothFraction = ScrollSmoother.defaultSmoothFraction
    @State private var glideStopThreshold = ScrollSmoother.defaultGlideStopThreshold
    @State private var loaded = false
    @State private var unavailable = false

    // SmartShift wheel mode.
    @State private var smartShiftSensitivity: Double = 16
    @State private var isFineTuningExpanded = false

    @State private var persistTask: Task<Void, Never>?

    private var config: Config { model.config }

    private var displayedLevel: Double {
        level ?? SmoothnessLevel.defaultValue
    }

    var body: some View {
        Form {
            directionSection
            wheelModeSection
            smoothScrollingSection
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: model.isConnected) { _, connected in
            if connected {
                loaded = false
                unavailable = false
                load()
            } else {
                flushPendingPersist()
            }
        }
        .onDisappear {
            flushPendingPersist()
        }
    }

    // MARK: - Sections

    private var directionSection: some View {
        Section {
            InvertScrollToggleRow()
        } header: {
            HStack(spacing: 6) {
                Text("Direction")
                HelpButton(text: "Invert if the wheel scrolls the wrong way compared to your other mice.")
            }
        }
    }

    private var wheelModeSection: some View {
        Section {
            SegmentedPillPicker(
                items: [nil, SmartShiftMode.freespin, SmartShiftMode.ratcheted]
                    + (model.capabilities.hasSmartShift ? [SmartShiftMode.smartshift] : []),
                selection: Binding(
                    get: { config.smartShiftMode },
                    set: { setSmartShiftMode($0) }),
                label: { mode in
                    switch mode {
                    case nil: return "Native"
                    case .freespin: return "Free-spin"
                    case .ratcheted: return "Ratcheted"
                    case .smartshift: return "SmartShift"
                    }
                })
            if config.smartShiftMode == .smartshift {
                smartShiftSensitivityRow()
            }
        } header: {
            HStack(spacing: 6) {
                Text("Wheel Mode")
                HelpButton(text: "Free-spin lets the wheel coast; ratcheted gives tactile steps; SmartShift switches automatically with scroll speed.")
            }
        }
    }

    private var smoothScrollingSection: some View {
        Section {
            if !model.isConnected {
                Text("Connect your mouse to configure smooth scrolling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if unavailable {
                Text("Smooth scrolling unavailable on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Smooth scrolling", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        guard loaded else { return }
                        apply()
                    }
                if enabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Smoothness")
                            HelpButton(text: HelpTexts.smoothness)
                            Spacer()
                            Text(smoothnessReadout)
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        PresetSlider(value: Binding(get: { displayedLevel },
                                                    set: { setLevel($0) }),
                                     currentLevel: level,
                                     onSelect: { applyPreset($0) },
                                     onReset: { resetToDefault() })
                    }
                    DisclosureGroup("Fine tuning", isExpanded: $isFineTuningExpanded) {
                        advancedPanel
                            .disabled(!enabled)
                    }
                }
            }
            HStack {
                SegmentedPillRow(segments: [
                    (label: "Scroll Thermograph…", action: { ScrollGraphWindow.shared.show() }, isHighlighted: false)
                ], compact: true)
                .help("Live thermal graph of raw vs smoothed scrolling in a separate window.")
                Spacer()
            }
        } header: {
            HStack(spacing: 6) {
                Text("Smooth Scrolling")
                HelpButton(text: "Replaces stepped wheel clicks with fluid glide. Fine tuning exposes the physics behind the presets.")
            }
        }
    }

    private var smoothnessReadout: String {
        guard let level else { return "Custom" }
        if let preset = SmoothnessPreset(level: level) {
            return "\(preset.displayName) (\(Int(level)))"
        }
        return "\(Int(level))"
    }

    // MARK: - Fine tuning panel (from the former Advanced tab)

    private var advancedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Momentum").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Toggle("Momentum", isOn: Binding(
                    get: { momentumEnabled },
                    set: { newValue in
                        momentumEnabled = newValue
                        customChange()
                    }
                ))
                HelpButton(text: HelpTexts.momentum)
            }
            sliderRow("Max boost", value: $maxBoost, range: 1.0...6.0, step: 0.1, format: "%.2f", help: HelpTexts.maxBoost)
            sliderRow("Momentum decay", value: $momentumDecay, range: 0.5...0.98, step: 0.01, format: "%.2f", help: HelpTexts.momentumDecay)
            sliderRow("Momentum stop", value: $momentumStopThreshold, range: 0.0...1.0, step: 0.05, format: "%.2f", help: HelpTexts.momentumStop)

            Divider().opacity(0.4)

            Text("Glide").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Toggle("Smoothing (glide)", isOn: Binding(
                    get: { smoothingEnabled },
                    set: { newValue in
                        smoothingEnabled = newValue
                        customChange()
                    }
                ))
                HelpButton(text: HelpTexts.smoothing)
            }
            sliderRow("Smooth fraction", value: $smoothFraction, range: 0.02...0.15, step: 0.005, format: "%.3f", help: HelpTexts.smoothFraction)
            sliderRow("Glide stop", value: $glideStopThreshold, range: 0.0...2.0, step: 0.1, format: "%.2f", help: HelpTexts.glideStop)

            Divider().opacity(0.4)

            Text("Feed & Ratchet Filtering").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            sliderRow("Pixels per notch", value: $pixelsPerNotch, range: 1...200, step: 1, format: "%.0f", help: HelpTexts.pixelsPerNotch)
            sliderRow("Accel window (s)", value: $accelerationWindow, range: 0.01...0.20, step: 0.01, format: "%.2f", help: HelpTexts.accelWindow)
            sliderRow("Feed gap timeout (s)", value: $feedGapTimeout, range: 0.02...0.30, step: 0.01, format: "%.2f", help: HelpTexts.feedGap)
            sliderRow("Bounce damping", value: $bounceDamping, range: 0.0...1.0, step: 0.05, format: "%.2f", help: HelpTexts.bounceDamping)

            HStack(spacing: 6) {
                Stepper("Reversal confirmation: \(reversalConfirmation)",
                        value: $reversalConfirmation, in: 1...5)
                    .onChange(of: reversalConfirmation) { _, _ in customChange() }
                HelpButton(text: HelpTexts.reversalConfirmation)
            }
            sliderRow("Direction threshold", value: $directionThreshold, range: 0.0...5.0, step: 0.25, format: "%.2f", help: HelpTexts.directionThreshold)

            HStack {
                Spacer()
                Button("Reset Fine Tuning") {
                    resetToDefault()
                }
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           format: String,
                           help: String) -> some View {
        HStack {
            Text(title).frame(width: 136, alignment: .leading)
            HelpButton(text: help)
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { newValue in
                                      value.wrappedValue = newValue
                                      customChange()
                                  }),
                   in: range, step: step)
            .controlSize(.small)
            .tint(Color.accentColor)
            .frame(height: 22)
            Text(String(format: format, value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    // MARK: - SmartShift

    private func smartShiftSensitivityRow() -> some View {
        HStack(spacing: 8) {
            Text("Sensitivity")
                .frame(width: 80, alignment: .leading)
            Slider(value: $smartShiftSensitivity, in: 1...100, step: 1) { editing in
                if !editing {
                    setSmartShiftSensitivity(Int(smartShiftSensitivity))
                }
            }
            .controlSize(.small)
            .tint(colorByValue(for: smartShiftSensitivity))
            .frame(height: 22)
            Text(verbatim: "\(Int(smartShiftSensitivity))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func colorByValue(for value: Double) -> Color {
        switch value {
        case ..<40: return .green
        case 40..<70: return .yellow
        default: return .red
        }
    }

    private func setSmartShiftMode(_ mode: SmartShiftMode?) {
        let updated = model.updateConfig { $0.smartShiftMode = mode }
        if mode == .smartshift {
            smartShiftSensitivity = Double(updated.smartShiftSensitivity ?? 16)
        }
        model.engine?.applyConfig()
    }

    private func setSmartShiftSensitivity(_ value: Int) {
        model.updateConfig { $0.smartShiftSensitivity = value }
        model.engine?.applyConfig()
    }

    // MARK: - Smooth scroll application

    private func setLevel(_ newValue: Double) {
        guard loaded else { return }
        level = newValue
        let p = SmoothnessLevel.parameters(level: newValue, multiplier: 8, invert: false)
        maxBoost = p.maxBoost
        momentumDecay = p.momentumDecay
        momentumEnabled = p.momentumEnabled
        smoothingEnabled = p.smoothingEnabled
        pixelsPerNotch = p.pixelsPerNotch
        smoothFraction = p.smoothFraction
        glideStopThreshold = p.glideStopThreshold
        accelerationWindow = p.accelerationWindow
        feedGapTimeout = p.feedGapTimeout
        momentumStopThreshold = p.momentumStopThreshold
        bounceWindow = p.bounceWindow
        bounceRatio = p.bounceRatio
        bounceDamping = p.bounceDamping
        reversalConfirmation = p.reversalConfirmation
        directionThreshold = p.directionThreshold
        applyLive()
    }

    private func applyPreset(_ preset: SmoothnessPreset) {
        guard loaded else { return }
        if preset == .native {
            enabled = false
        } else {
            setLevel(preset.level)
        }
    }

    private func resetToDefault() {
        guard loaded else { return }
        setLevel(SmoothnessLevel.defaultValue)
    }

    private func currentParams() -> ScrollSmoother.Parameters {
        ScrollSmoother.Parameters(
            multiplier: 8,
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

    private func customChange() {
        guard loaded else { return }
        level = nil
        applyLive()
    }

    private func apply() {
        persistTask?.cancel()
        persistTask = nil
        let targetEnabled = enabled
        let targetLevel = level
        let targetAdvanced = storedAdvanced
        model.updateConfig {
            $0.smoothScrollEnabled = targetEnabled
            $0.smoothScrollLevel = targetLevel
            $0.smoothScrollAdvanced = targetAdvanced
        }
        model.engine?.applyConfig()
    }

    /// Persists config debounced: dragging the smoothness slider fires this
    /// per tick, and synchronous JSON I/O on the main thread here shows up as
    /// a wheel hitch. Live parameter application stays immediate above.
    private func applyLive() {
        model.engine?.updateSmoothParameters(currentParams())
        persistTask?.cancel()
        let targetEnabled = enabled
        let targetLevel = level
        let targetAdvanced = storedAdvanced
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.persistTask = nil
                self.model.updateConfig {
                    $0.smoothScrollEnabled = targetEnabled
                    $0.smoothScrollLevel = targetLevel
                    $0.smoothScrollAdvanced = targetAdvanced
                }
            }
        }
    }

    private func flushPendingPersist() {
        guard let task = persistTask else { return }
        task.cancel()
        persistTask = nil
        let targetEnabled = enabled
        let targetLevel = level
        let targetAdvanced = storedAdvanced
        model.updateConfig {
            $0.smoothScrollEnabled = targetEnabled
            $0.smoothScrollLevel = targetLevel
            $0.smoothScrollAdvanced = targetAdvanced
        }
    }

    private var storedAdvanced: ScrollSmoother.Parameters? {
        level == nil ? currentParams() : nil
    }

    private func load() {
        let cfg = model.config
        smartShiftSensitivity = Double(cfg.smartShiftSensitivity ?? 16)

        guard model.isConnected else {
            unavailable = false
            return
        }
        guard model.engine?.hiResWheelService != nil else {
            unavailable = true
            return
        }
        unavailable = false
        enabled = cfg.smoothScrollEnabled == true
        level = cfg.smoothScrollLevel
        let params = cfg.smoothScrollAdvanced
            ?? SmoothnessLevel.parameters(level: level ?? SmoothnessLevel.defaultValue,
                                          multiplier: 8, invert: false)
        maxBoost = params.maxBoost
        momentumDecay = params.momentumDecay
        momentumEnabled = params.momentumEnabled
        pixelsPerNotch = params.pixelsPerNotch
        accelerationWindow = params.accelerationWindow
        feedGapTimeout = params.feedGapTimeout
        momentumStopThreshold = params.momentumStopThreshold
        bounceWindow = params.bounceWindow
        bounceRatio = params.bounceRatio
        bounceDamping = params.bounceDamping
        reversalConfirmation = params.reversalConfirmation
        directionThreshold = params.directionThreshold
        smoothingEnabled = params.smoothingEnabled
        smoothFraction = params.smoothFraction
        glideStopThreshold = params.glideStopThreshold
        loaded = true
    }
}

/// Moved from GeneralTabView — belongs with the other wheel settings.
struct InvertScrollToggleRow: View {
    @State private var inverted = false
    @State private var loaded = false
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Toggle("Invert scroll direction", isOn: $inverted)
            .onChange(of: inverted) { _, _ in
                guard loaded else { return }
                apply()
            }
            .onAppear {
                load()
            }
            .onChange(of: model.isConnected) { _, connected in
                if connected {
                    loaded = false
                    load()
                }
            }
    }

    private func load() {
        let stored = model.config.invertScrollDirection
        guard let service = model.engine?.hiResWheelService else {
            self.inverted = stored ?? false
            self.loaded = true
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let inverted = stored ?? ((try? service.getWheelMode())?.inverted ?? false)
            DispatchQueue.main.async {
                self.inverted = inverted
                self.loaded = true
            }
        }
    }

    private func apply() {
        model.updateConfig { $0.invertScrollDirection = inverted }
        model.engine?.applyConfig()
    }
}
