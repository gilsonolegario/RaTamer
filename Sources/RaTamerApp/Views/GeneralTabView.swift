import AppKit
import SwiftUI
import RaTamerCore

struct GeneralTabView: View {
    @ObservedObject private var loginItem = LoginItem.shared
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Form {
                Section {
                    PermissionStatusRow()
                } header: {
                    HStack {
                        Text("Accessibility")
                        HelpButton(text: "RaTamer needs accessibility permission to remap buttons and post keyboard/mouse events.")
                    }
                }
                Section {
                    HStack {
                        Toggle("Enable remapping", isOn: $model.remappingEnabled)
                        HelpButton(text: "When off, buttons fall back to native behavior until re-enabled.")
                    }
                } header: {
                    Text("Remapping")
                }
                Section {
                    HStack {
                        TerminalProtectionRow()
                        HelpButton(text: "Blocks synthesized keys, clicks and scrolls while a terminal app is focused, so shortcuts and gestures never land as text in tmux.")
                    }
                } header: {
                    Text("Terminal Protection")
                }
                Section {
                    DPISliderRow()
                    DPICyclePresetsRow()
                    HStack {
                        Spacer()
                        HelpButton(text: "Sensor resolution. Assign \"Cycle DPI\" to a button in the Buttons tab to switch presets on the fly.")
                    }
                } header: {
                    Text("DPI")
                }
                Section {
                    HStack {
                        Toggle("Start at login", isOn: $loginItem.isEnabled)
                        HelpButton(text: "Launches RaTamer when you log in so button remapping is always available.")
                    }
                } header: {
                    Text("Login")
                }
                Section {
                    HStack {
                        DockIconRow()
                        HelpButton(text: "Hides the Dock icon and keeps RaTamer accessible only from the menu bar and popover.")
                    }
                } header: {
                    Text("Dock")
                }
            }
            .formStyle(.grouped)
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
            SegmentedPillRow(segments: [
                (label: "Fix", action: { openAccessibilitySettings() }, isHighlighted: true)
            ], compact: true)
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
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Group {
            if values.count > 1 && model.isConnected {
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
            } else if model.isConnected || model.dpiCache != nil {
                Text(values.isEmpty ? "Loading DPI…" : "DPI feature unavailable on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect your mouse to see DPI options")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
        .onChange(of: model.dpiCache) { _, cache in
            if let cache {
                self.values = cache.values
                self.current = cache.value
            } else {
                self.values = []
            }
        }
        .onChange(of: model.isConnected) { _, connected in
            if connected { load() }
        }
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
                HelpButton(text: "Assign 'Cycle DPI' to a button in the Buttons tab to switch presets on the fly. Empty uses defaults.")
                Spacer()
                SegmentedPillRow(segments: [
                    (label: "Reset", action: { reset() }, isHighlighted: configured)
                ])
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

