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
    @State private var config = AppModel.shared.configStore.load()

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

    @State private var persistTask: Task<Void, Never>?

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
    }

    // MARK: - Sections

    private var directionSection: some View {
        Section {
            InvertScrollToggleRow()
        } header: {
            Text("Direction")
        } footer: {
            Text("Invert if the wheel scrolls the wrong way compared to your other mice.")
        }
    }

    private var wheelModeSection: some View {
        Section {
            Picker("Mode", selection: Binding(
                get: { config.smartShiftMode },
                set: { setSmartShiftMode($0) }))
            {
                Label("Native (default)", systemImage: "arrow.uturn.left.circle")
                    .tag(SmartShiftMode?.none)
                Label("Free-spin", systemImage: "wind")
                    .tag(SmartShiftMode?.some(.freespin))
                Label("Ratcheted", systemImage: "digitalcrown.arrow.clockwise")
                    .tag(SmartShiftMode?.some(.ratcheted))
                if model.capabilities.hasSmartShift {
                    Label("SmartShift (auto)", systemImage: "bolt.badge.automatic")
                        .tag(SmartShiftMode?.some(.smartshift))
                }
            }
            if config.smartShiftMode == .smartshift {
                smartShiftSensitivityRow()
            }
        } header: {
            Text("Wheel Mode")
        } footer: {
            Text("Free-spin lets the wheel coast; ratcheted gives tactile steps; SmartShift switches automatically with scroll speed.")
        }
    }

    private var smoothScrollingSection: some View {
        Section {
            if unavailable {
                Text("Smooth scrolling unavailable on this device")
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
                            Text(level == nil ? "custom" : "\(Int(displayedLevel))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        PresetSlider(value: Binding(get: { displayedLevel },
                                                    set: { setLevel($0) }),
                                     currentLevel: level,
                                     onSelect: { applyPreset($0) },
                                     onReset: { resetToDefault() })
                    }
                    DisclosureGroup("Fine tuning") {
                        advancedPanel
                            .disabled(!enabled)
                    }
                }
                Button(action: { ScrollGraphWindow.shared.show() }) {
                    Label("Open Scroll Thermograph…", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.bordered)
                .help("Live thermal graph of raw vs smoothed scrolling in a separate window.")
            }
        } header: {
            Text("Smooth Scrolling")
        } footer: {
            Text("Replaces stepped wheel clicks with fluid glide. Fine tuning exposes the physics behind the presets.")
        }
    }

    // MARK: - Fine tuning panel (from the former Advanced tab)

    private var advancedPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Momentum").font(.caption).fontWeight(.semibold)
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
            sliderRow("Max boost", value: $maxBoost, range: 1.0...6.0, step: 0.1, help: HelpTexts.maxBoost)
            sliderRow("Momentum decay", value: $momentumDecay, range: 0.5...0.98, step: 0.01, help: HelpTexts.momentumDecay)
            sliderRow("Momentum stop", value: $momentumStopThreshold, range: 0.0...1.0, step: 0.05, help: HelpTexts.momentumStop)

            Text("Glide").font(.caption).fontWeight(.semibold)
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
            sliderRow("Smooth fraction", value: $smoothFraction, range: 0.02...0.15, step: 0.01, help: HelpTexts.smoothFraction)
            sliderRow("Glide stop", value: $glideStopThreshold, range: 0.0...2.0, step: 0.1, help: HelpTexts.glideStop)

            Text("Feed").font(.caption).fontWeight(.semibold)
            sliderRow("Pixels per notch", value: $pixelsPerNotch, range: 1...200, step: 1, help: HelpTexts.pixelsPerNotch)
            sliderRow("Accel window (s)", value: $accelerationWindow, range: 0.01...0.20, step: 0.01, help: HelpTexts.accelWindow)
            sliderRow("Feed gap timeout (s)", value: $feedGapTimeout, range: 0.02...0.30, step: 0.01, help: HelpTexts.feedGap)

            Text("Bounce").font(.caption).fontWeight(.semibold)
            sliderRow("Bounce window (s)", value: $bounceWindow, range: 0.0...0.20, step: 0.005, help: HelpTexts.bounceWindow)
            sliderRow("Bounce ratio", value: $bounceRatio, range: 0.1...1.0, step: 0.05, help: HelpTexts.bounceRatio)
            sliderRow("Bounce damping", value: $bounceDamping, range: 0.0...1.0, step: 0.05, help: HelpTexts.bounceDamping)

            Text("Direction").font(.caption).fontWeight(.semibold)
            HStack(spacing: 6) {
                Stepper("Reversal confirmation: \(reversalConfirmation)",
                        value: $reversalConfirmation, in: 1...5)
                    .onChange(of: reversalConfirmation) { _, _ in customChange() }
                HelpButton(text: HelpTexts.reversalConfirmation)
            }
            sliderRow("Direction threshold", value: $directionThreshold, range: 0.0...5.0, step: 0.25, help: HelpTexts.directionThreshold)
        }
        .padding(.top, 2)
    }

    private func sliderRow(_ title: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           help: String) -> some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            HelpButton(text: help)
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { newValue in
                                      withAnimation(.snappy(duration: 0.25)) {
                                          value.wrappedValue = newValue
                                      }
                                      customChange()
                                  }),
                   in: range, step: step)
            .controlSize(.small)
            .tint(Color.accentColor)
            .frame(height: 22)
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 52, alignment: .trailing)
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
            Text("\(Int(smartShiftSensitivity))")
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
        config.smartShiftMode = mode
        if mode == .smartshift {
            smartShiftSensitivity = Double(config.smartShiftSensitivity ?? 16)
        }
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func setSmartShiftSensitivity(_ value: Int) {
        config.smartShiftSensitivity = value
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    // MARK: - Smooth scroll application (unchanged from the former Advanced tab)

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
        var config = AppModel.shared.configStore.load()
        config.smoothScrollEnabled = enabled
        config.smoothScrollLevel = level
        config.smoothScrollAdvanced = storedAdvanced
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    /// Persists config debounced: dragging the smoothness slider fires this
    /// per tick, and synchronous JSON I/O on the main thread here shows up as
    /// a wheel hitch. Live parameter application stays immediate above.
    private func applyLive() {
        AppModel.shared.engine?.updateSmoothParameters(currentParams())
        persistTask?.cancel()
        persistTask = Task { [enabled, level, storedAdvanced] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            var config = AppModel.shared.configStore.load()
            config.smoothScrollEnabled = enabled
            config.smoothScrollLevel = level
            config.smoothScrollAdvanced = storedAdvanced
            try? AppModel.shared.configStore.save(config)
        }
    }

    private var storedAdvanced: ScrollSmoother.Parameters? {
        level == nil ? currentParams() : nil
    }

    private func load() {
        config = AppModel.shared.configStore.load()
        smartShiftSensitivity = Double(config.smartShiftSensitivity ?? 16)

        guard AppModel.shared.engine?.hiResWheelService != nil else {
            unavailable = true
            return
        }
        enabled = config.smoothScrollEnabled == true
        level = config.smoothScrollLevel
        let params = config.smoothScrollAdvanced
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
    @State private var unavailable = false

    var body: some View {
        Group {
            if unavailable {
                Text("Scroll direction feature unavailable on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Invert scroll direction", isOn: $inverted)
                    .onChange(of: inverted) { _, _ in
                        guard loaded else { return }
                        apply()
                    }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let service = AppModel.shared.engine?.hiResWheelService else {
            unavailable = true
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let hasInvert = (try? service.getInfo())?.hasInvert == true
            guard hasInvert else {
                DispatchQueue.main.async { self.unavailable = true }
                return
            }
            let stored = AppModel.shared.configStore.load().invertScrollDirection
            let inverted = stored ?? ((try? service.getWheelMode())?.inverted ?? false)
            DispatchQueue.main.async {
                self.inverted = inverted
                self.loaded = true
            }
        }
    }

    private func apply() {
        var config = AppModel.shared.configStore.load()
        config.invertScrollDirection = inverted
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }
}
