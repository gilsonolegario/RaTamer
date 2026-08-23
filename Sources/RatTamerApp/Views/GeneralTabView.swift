import AppKit
import SwiftUI
import RatTamerCore

struct GeneralTabView: View {
    @ObservedObject private var loginItem = LoginItem.shared
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        ScrollView {
            Form {
                Section("Accessibility") {
                    PermissionStatusRow()
                    Text("RatTamer needs accessibility permission to remap buttons and post keyboard/mouse events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Remapping") {
                    Toggle("Enable remapping", isOn: $model.remappingEnabled)
                    Text("When off, buttons fall back to native behavior until re-enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Terminal Protection") {
                    TerminalProtectionRow()
                    Text("Blocks synthesized keys, clicks and scrolls while a terminal app is focused, so shortcuts and gestures never land as text in tmux. Native mouse behavior is preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Scrolling") {
                    ScrollDirectionToggleRow()
                    SmoothScrollRow()
                }
                Section("Pointer Resolution") {
                    DPISliderRow()
                    DPICyclePresetsRow()
                }
                Section("Battery") {
                    BatteryStatusRow()
                }
                Section("Login") {
                    Toggle("Start at login", isOn: $loginItem.isEnabled)
                    Text("Launches RatTamer when you log in so button remapping is always available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Dock") {
                    DockIconRow()
                    Text("Hides the Dock icon and keeps RatTamer accessible only from the menu bar and popover.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct TerminalProtectionRow: View {
    @State private var protectTerminals = true
    @State private var loaded = false

    var body: some View {
        Toggle("Block events in terminal apps", isOn: $protectTerminals)
            .onChange(of: protectTerminals) { _, _ in
                guard loaded else { return }
                apply()
            }
            .onAppear(perform: load)
    }

    private func load() {
        protectTerminals = AppModel.shared.configStore.load().protectTerminals ?? true
        loaded = true
    }

    private func apply() {
        var config = AppModel.shared.configStore.load()
        config.protectTerminals = protectTerminals
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }
}

struct DockIconRow: View {
    @State private var menuBarOnly = false
    @State private var loaded = false

    var body: some View {
        Toggle("Menu bar only (hide from Dock)", isOn: $menuBarOnly)
            .onChange(of: menuBarOnly) { _, _ in
                guard loaded else { return }
                apply()
            }
            .onAppear(perform: load)
    }

    private func load() {
        menuBarOnly = AppModel.shared.configStore.load().menuBarOnly == true
        loaded = true
    }

    private func apply() {
        var config = AppModel.shared.configStore.load()
        config.menuBarOnly = menuBarOnly
        try? AppModel.shared.configStore.save(config)
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
    }
}

struct PermissionStatusRow: View {
    @State private var accessibility = false

    var body: some View {
        HStack {
            Label("Accessibility", systemImage: accessibility ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(accessibility ? .green : .red)
            Button("Fix") { openAccessibilitySettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Spacer()
            Text(AppModel.shared.statusText).font(.caption)
        }
        .onAppear {
            accessibility = Permissions.isAccessibilityTrusted()
        }
    }

    private func openAccessibilitySettings() {
        Permissions.requestAccessibility()
        accessibility = Permissions.isAccessibilityTrusted()
    }
}

struct DPISliderRow: View {
    @State private var values: [UInt16] = []
    @State private var current: Double = 1000

    var body: some View {
        Group {
            if values.count > 1 {
                Slider(value: $current, in: closedRange, step: step) { editing in
                    if !editing { apply(UInt16(current)) }
                }
                .controlSize(.small)
                .tint(Color.accentColor)
                .frame(height: 22)
                HStack {
                    Text("\(Int(current)) DPI")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("DPI feature unavailable on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
    }

    private var closedRange: ClosedRange<Double> {
        Double(values.first ?? 0)...Double(values.last ?? 0)
    }

    private var step: Double {
        guard values.count >= 2 else { return 1 }
        let gaps = zip(values.dropFirst(), values).map { Double($0 - $1) }
        return gaps.min() ?? 1
    }

    private func load() {
        guard let service = AppModel.shared.engine?.dpiService else { return }
        let currentValue = current
        DispatchQueue.global(qos: .utility).async {
            let values = (try? service.getSensorDpiList(sensor: 0)) ?? []
            if values.count > 1 {
                let stored = AppModel.shared.configStore.load().dpiValue
                let selected: Double
                if let stored {
                    selected = Double(stored)
                } else if let info = try? service.getSensorDpi(sensor: 0) {
                    selected = Double(info.dpi)
                } else {
                    selected = currentValue
                }
                let cache = DPICache(values: values, value: selected)
                DispatchQueue.main.async {
                    self.values = values
                    self.current = selected
                    AppModel.shared.dpiCache = cache
                }
            } else {
                DispatchQueue.main.async { self.values = values }
            }
        }
    }

    private func apply(_ dpi: UInt16) {
        var config = AppModel.shared.configStore.load()
        config.dpiValue = dpi
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.dpiCache = DPICache(values: values, value: Double(dpi))
        AppModel.shared.engine?.applyConfig()
    }
}

struct DPICyclePresetsRow: View {
    @State private var text = ""
    @State private var configured = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Cycle presets (comma separated)", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Text("Assign 'Cycle DPI' to a button in the Buttons tab. Empty uses defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { reset() }
                    .controlSize(.small)
                    .disabled(!configured)
            }
        }
        .padding(.top, 4)
        .onAppear(perform: load)
    }

    private func load() {
        let config = AppModel.shared.configStore.load()
        configured = config.dpiCycleValues != nil
        text = config.dpiCycleValues?.map(String.init).joined(separator: ", ") ?? ""
    }

    private func save() {
        var config = AppModel.shared.configStore.load()
        config.dpiCycleValues = parse(text)
        try? AppModel.shared.configStore.save(config)
        configured = config.dpiCycleValues != nil
        AppModel.shared.engine?.applyConfig()
    }

    private func reset() {
        var config = AppModel.shared.configStore.load()
        config.dpiCycleValues = nil
        try? AppModel.shared.configStore.save(config)
        configured = false
        text = ""
        AppModel.shared.engine?.applyConfig()
    }

    private func parse(_ input: String) -> [UInt16]? {
        var seen = Set<UInt16>()
        var result: [UInt16] = []
        for part in input.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let value = UInt16(trimmed), !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result.isEmpty ? nil : result
    }
}

struct ScrollDirectionToggleRow: View {
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

struct BatteryStatusRow: View {
    @State private var info: BatteryInfo?

    var body: some View {
        Group {
            if let info {
                HStack {
                    Circle()
                        .fill(color(for: info))
                        .frame(width: 10, height: 10)
                    Text(title(for: info))
                    Spacer()
                }
            } else {
                Text("Battery feature unavailable on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let service = AppModel.shared.engine?.batteryStatusService else { return }
        DispatchQueue.global(qos: .utility).async {
            let info = try? service.getBatteryInfo()
            DispatchQueue.main.async { self.info = info }
        }
    }

    private func color(for info: BatteryInfo) -> Color {
        switch info.state {
        case .full: return .green
        default: break
        }
        switch info.level {
        case .full: return .green
        case .good: return .yellow
        case .low: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }

    private func title(for info: BatteryInfo) -> String {
        BatteryDisplay.title(for: info)
    }
}

struct SmoothScrollRow: View {
    @State private var enabled = false
    @State private var level: Double?
    @State private var loaded = false
    @State private var unavailable = false

    private var displayedLevel: Double {
        level ?? SmoothnessLevel.defaultValue
    }

    var body: some View {
        Group {
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
                }
            }
        }
        .onAppear(perform: load)
    }

    private func setLevel(_ newValue: Double) {
        guard loaded else { return }
        level = newValue
        apply()
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

    private func apply() {
        var config = AppModel.shared.configStore.load()
        config.smoothScrollEnabled = enabled
        config.smoothScrollLevel = level
        if level != nil {
            config.smoothScrollAdvanced = nil
        }
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func load() {
        guard AppModel.shared.engine?.hiResWheelService != nil else {
            unavailable = true
            return
        }
        let config = AppModel.shared.configStore.load()
        enabled = config.smoothScrollEnabled == true
        level = config.smoothScrollLevel
        loaded = true
    }
}
