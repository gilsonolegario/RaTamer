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
                HStack(spacing: 6) {
                    Text("Status & Permissions")
                    HelpButton(text: "RaTamer needs accessibility permission to remap buttons and post keyboard/mouse events.")
                }
            }

            Section {
                Toggle("Enable remapping", isOn: $model.remappingEnabled)
                TerminalProtectionRow()
            } header: {
                HStack(spacing: 6) {
                    Text("Behavior")
                    HelpButton(text: "Disable remapping to temporarily revert to native mouse behavior. Terminal protection blocks synthesized keys, clicks, and scrolls while a terminal app is focused.")
                }
            }

            Section {
                DPISliderRow()
                DPICyclePresetsRow()
            } header: {
                HStack(spacing: 6) {
                    Text("Pointer & DPI")
                    HelpButton(text: "Adjust sensor resolution or define comma-separated presets for the \"Cycle DPI\" button action.")
                }
            }

            Section {
                Toggle("Start at login", isOn: $loginItem.isEnabled)
                DockIconRow()
            } header: {
                HStack(spacing: 6) {
                    Text("System")
                    HelpButton(text: "Launch RaTamer automatically at login or hide its Dock icon to keep it strictly in the menu bar.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct TerminalProtectionRow: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Toggle(
            "Block events in terminal apps",
            isOn: Binding(
                get: { model.config.protectTerminals ?? true },
                set: { newValue in
                    model.updateConfig { $0.protectTerminals = newValue }
                    model.engine?.applyConfig()
                }
            )
        )
    }
}

struct DockIconRow: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Toggle(
            "Menu bar only (hide from Dock)",
            isOn: Binding(
                get: { model.config.menuBarOnly == true },
                set: { newValue in
                    model.updateConfig { $0.menuBarOnly = newValue }
                    ActivationPolicyHelper.applyValue(menuBarOnly: newValue, reason: "toggle")
                }
            )
        )
    }
}

struct PermissionStatusRow: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label {
                    Text("Accessibility")
                } icon: {
                    Image(systemName: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                }
                Spacer()
                if model.accessibilityTrusted {
                    Text("Granted")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    SegmentedPillRow(segments: [
                        (label: "Grant Access…", action: { openAccessibilitySettings() }, isHighlighted: true)
                    ], compact: true)
                }
            }
            Divider().opacity(0.4)
            HStack(spacing: 8) {
                Label {
                    Text(model.isConnected ? model.deviceName : "Mouse")
                } icon: {
                    Image(systemName: model.isConnected ? "computermouse.fill" : "computermouse")
                        .foregroundStyle(connectionColor)
                }
                Spacer()
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !model.isConnected && !model.isReconnecting {
                    SegmentedPillRow(segments: [
                        (label: "Reconnect", action: { model.engine?.reconnect() }, isHighlighted: false)
                    ], compact: true)
                }
            }
        }
        .onAppear {
            model.refreshAccessibility()
        }
    }

    private var connectionColor: Color {
        if model.isReconnecting { return .orange }
        return model.isConnected ? .green : .secondary
    }

    private func openAccessibilitySettings() {
        Permissions.requestAccessibility()
        model.refreshAccessibility()
    }
}

struct DPISliderRow: View {
    @State private var values: [UInt16] = []
    @State private var current: Double = 1000
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        Group {
            if dpiAvailable {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text(verbatim: "\(Int(current)) DPI")
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { current },
                            set: { newValue in
                                current = Double(nearestDPI(to: newValue))
                            }
                        ),
                        in: closedRange
                    ) { editing in
                        if !editing { apply(nearestDPI(to: current)) }
                    }
                    .controlSize(.small)
                    .tint(Color.accentColor)
                    .frame(height: 22)
                    if let lower = values.first, let upper = values.last {
                        HStack {
                            Text(verbatim: "\(lower)")
                            Spacer()
                            Text(verbatim: "\(upper)")
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    }
                }
            } else if model.isConnected {
                Text(values.isEmpty ? "Loading DPI…" : "DPI feature unavailable on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect your mouse to adjust sensor DPI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            syncFromCache()
            load()
        }
        .onChange(of: model.dpiCache) { _, _ in
            syncFromCache()
        }
        .onChange(of: model.isConnected) { _, connected in
            if connected {
                load()
            } else {
                values = []
            }
        }
    }

    private var dpiAvailable: Bool {
        guard let first = values.first, let last = values.last else { return false }
        return values.count > 1 && first < last
    }

    private var closedRange: ClosedRange<Double> {
        let lower = Double(values.first ?? 400)
        let upper = max(lower + 1, Double(values.last ?? 4000))
        return lower...upper
    }

    private func nearestDPI(to target: Double) -> UInt16 {
        guard !values.isEmpty else { return UInt16(max(100, target.rounded())) }
        return values.min(by: { abs(Double($0) - target) < abs(Double($1) - target) }) ?? values[0]
    }

    private func syncFromCache() {
        guard let cache = model.dpiCache else {
            if !model.isConnected { values = [] }
            return
        }
        let sorted = Array(Set(cache.values)).sorted()
        guard sorted.count > 1 else { return }
        self.values = sorted
        self.current = Double(sorted.min(by: { abs(Double($0) - cache.value) < abs(Double($1) - cache.value) }) ?? sorted[0])
    }

    private func load() {
        guard let service = model.engine?.dpiService else { return }
        let currentValue = current
        DispatchQueue.global(qos: .utility).async {
            let raw = (try? service.getSensorDpiList(sensor: 0)) ?? []
            let values = Array(Set(raw)).sorted()
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
                let snapped = Double(values.min(by: { abs(Double($0) - selected) < abs(Double($1) - selected) }) ?? values[0])
                let cache = DPICache(values: values, value: snapped)
                DispatchQueue.main.async {
                    self.values = values
                    self.current = snapped
                    AppModel.shared.dpiCache = cache
                }
            } else {
                DispatchQueue.main.async { self.values = values }
            }
        }
    }

    private func apply(_ dpi: UInt16) {
        current = Double(dpi)
        model.updateConfig { $0.dpiValue = dpi }
        model.dpiCache = DPICache(values: values, value: Double(dpi))
        model.engine?.applyConfig()
    }
}

struct DPICyclePresetsRow: View {
    @ObservedObject private var model = AppModel.shared
    @State private var text = ""
    @State private var validationWarning: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        let configured = model.config.dpiCycleValues != nil
        let activePresets = model.config.dpiCycleValues
            ?? DPICycle.recommendedPresets(from: model.dpiCache?.values ?? [])

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Cycle presets (e.g. 1000, 1600, 2400, 4000)", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(save)
                SegmentedPillRow(segments: [
                    (label: "Apply", action: { save() }, isHighlighted: hasUnsavedChanges),
                    (label: "Reset", action: { reset() }, isHighlighted: configured)
                ], compact: true)
            }
            if let validationWarning {
                Text(validationWarning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 5) {
                Text(configured ? "Active presets:" : "Default presets:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(activePresets, id: \.self) { dpi in
                    Text(verbatim: "\(dpi)")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
            }
        }
        .padding(.top, 2)
        .onAppear(perform: syncTextFromConfig)
        .onChange(of: model.config.dpiCycleValues) { _, _ in
            if !isFocused { syncTextFromConfig() }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && hasUnsavedChanges {
                save()
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        let currentText = model.config.dpiCycleValues?.map(String.init).joined(separator: ", ") ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines) != currentText
    }

    private func syncTextFromConfig() {
        text = model.config.dpiCycleValues?.map(String.init).joined(separator: ", ") ?? ""
        validationWarning = nil
    }

    private func save() {
        let (parsed, ignoredCount) = parse(text)
        model.updateConfig { $0.dpiCycleValues = parsed }
        text = parsed?.map(String.init).joined(separator: ", ") ?? ""
        validationWarning = ignoredCount > 0
            ? "Ignored \(ignoredCount) invalid DPI value(s) outside 100–30000."
            : nil
        model.engine?.applyConfig()
    }

    private func reset() {
        model.updateConfig { $0.dpiCycleValues = nil }
        text = ""
        validationWarning = nil
        model.engine?.applyConfig()
    }

    private func parse(_ input: String) -> (values: [UInt16]?, ignored: Int) {
        var seen = Set<UInt16>()
        var result: [UInt16] = []
        var ignored = 0
        for part in input.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let value = UInt16(trimmed), value >= 100, value <= 30000 else {
                ignored += 1
                continue
            }
            if !seen.contains(value) {
                seen.insert(value)
                result.append(value)
            }
        }
        return (result.isEmpty ? nil : result, ignored)
    }
}

