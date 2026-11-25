import SwiftUI
import RaTamerCore

struct MenuBarPopoverView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var battery = BatteryMonitor.shared
    @ObservedObject private var loginItem = LoginItem.shared
    @State private var hoveredRow: String?
    @State private var dpi: Double = 1000
    @State private var dpiValues: [UInt16] = []
    @State private var dpiLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusHeader

            if !model.accessibilityTrusted {
                accessibilityBanner
            }

            separator

            dpiRow

            separator

            VStack(spacing: 2) {
                toggleRow(icon: "wand.and.stars", label: "Enable remapping", isOn: $model.remappingEnabled)
                toggleRow(icon: "power.circle", label: "Start at login", isOn: $loginItem.isEnabled)
            }

            separator

            VStack(spacing: 2) {
                actionRow(icon: "gearshape", label: "Settings…", shortcut: "⌘,",
                          isHovered: hoveredRow == "settings",
                          onHover: { hoveredRow = $0 ? "settings" : nil }) {
                    SettingsWindow.shared.show()
                }
                actionRow(icon: "arrow.clockwise", label: "Reconnect", shortcut: nil,
                          isHovered: hoveredRow == "reconnect",
                          onHover: { hoveredRow = $0 ? "reconnect" : nil }) {
                    model.engine?.reconnect()
                }
                actionRow(icon: "power", label: "Quit RaTamer", shortcut: "⌘Q",
                          isHovered: hoveredRow == "quit",
                          onHover: { hoveredRow = $0 ? "quit" : nil }) {
                    // Tear down the process-lifetime keyboard-layout observer so it
                    // never outlives the engine (ActionEngine.shutdown is idempotent).
                    ActionEngine.shutdown()
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 288)
        .onAppear {
            BatteryMonitor.shared.start()
            BatteryMonitor.shared.refresh()
            syncFromDPICache()
            loadDPI()
        }
        .onChange(of: model.dpiCache) { _, _ in
            syncFromDPICache()
        }
        .onChange(of: model.isConnected) { _, connected in
            if connected {
                loadDPI()
                BatteryMonitor.shared.refresh()
            } else {
                dpiValues = []
                dpiLoaded = false
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: model.isConnected ? "computermouse.fill" : "computermouse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(model.isConnected ? model.deviceName : "RaTamer")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: model.isConnected)
                }
                Text(model.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if let info = battery.info {
                batteryBadge(for: info)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func batteryBadge(for info: BatteryInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: BatteryDisplay.symbol(for: info))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(batteryColor(for: info))
            Text(batteryShortLabel(for: info))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .help(BatteryDisplay.title(for: info))
    }

    private var accessibilityBanner: some View {
        Button {
            Permissions.requestAccessibility()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Grant Accessibility for shortcuts & scroll")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text("Fix")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    private var dpiRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("Pointer Resolution")
                    .font(.callout)
                Spacer()
                if dpiAvailable {
                    Text(verbatim: "\(Int(dpi)) DPI")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if dpiAvailable {
                Slider(
                    value: Binding(
                        get: { dpi },
                        set: { newValue in
                            dpi = Double(nearestDPI(to: newValue, in: dpiValues))
                        }
                    ),
                    in: dpiRange
                ) { editing in
                    if !editing { applyDPI() }
                }
                .controlSize(.small)
                .tint(Color.accentColor)
                .frame(height: 22)
            } else {
                Text(model.isConnected ? "DPI feature unavailable on this device" : "Connect mouse to adjust DPI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var dpiAvailable: Bool {
        guard let first = dpiValues.first, let last = dpiValues.last else { return false }
        return dpiValues.count > 1 && first < last
    }

    private var dpiRange: ClosedRange<Double> {
        let lower = Double(dpiValues.first ?? 400)
        let upper = max(lower + 1, Double(dpiValues.last ?? 4000))
        return lower...upper
    }

    private func nearestDPI(to target: Double, in values: [UInt16]) -> UInt16 {
        guard !values.isEmpty else { return UInt16(max(100, target.rounded())) }
        return values.min(by: { abs(Double($0) - target) < abs(Double($1) - target) }) ?? values[0]
    }

    private func syncFromDPICache() {
        guard let cache = model.dpiCache else { return }
        let sorted = Array(Set(cache.values)).sorted()
        guard sorted.count > 1 else { return }
        self.dpiValues = sorted
        self.dpi = Double(nearestDPI(to: cache.value, in: sorted))
        self.dpiLoaded = true
    }

    private func loadDPI() {
        guard let service = model.engine?.dpiService else { return }
        let currentDPI = dpi
        DispatchQueue.global(qos: .utility).async {
            let rawValues = (try? service.getSensorDpiList(sensor: 0)) ?? []
            let values = Array(Set(rawValues)).sorted()
            guard values.count > 1 else {
                DispatchQueue.main.async { self.dpiValues = values }
                return
            }
            var selected = currentDPI
            if let stored = AppModel.shared.configStore.load().dpiValue {
                selected = Double(stored)
            } else if let info = try? service.getSensorDpi(sensor: 0) {
                selected = Double(info.dpi)
            }
            let snapped = Double(self.nearestDPI(to: selected, in: values))
            let cache = DPICache(values: values, value: snapped)
            DispatchQueue.main.async {
                self.dpiValues = values
                self.dpi = snapped
                self.dpiLoaded = true
                AppModel.shared.dpiCache = cache
            }
        }
    }

    private func applyDPI() {
        guard dpiLoaded else { return }
        let snapped = nearestDPI(to: dpi, in: dpiValues)
        dpi = Double(snapped)
        model.updateConfig { $0.dpiValue = snapped }
        model.dpiCache = DPICache(values: dpiValues, value: Double(snapped))
        model.engine?.applyConfig()
    }

    private func toggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.callout)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .focusEffectDisabled()
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private func actionRow(icon: String, label: String, shortcut: String?,
                           isHovered: Bool,
                           onHover: @escaping (Bool) -> Void,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .styledButton(hoverScale: 1.0, pressScale: 0.98)
        .onHover(perform: onHover)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func batteryShortLabel(for info: BatteryInfo) -> String {
        switch info.state {
        case .full: return "100%"
        case .charging, .recharging: return info.capacity > 0 ? "\(info.capacity)%" : "Charging"
        case .discharging: return "\(info.capacity)%"
        case .notCharging, .unknown: return info.level.rawValue.capitalized
        }
    }

    private func batteryColor(for info: BatteryInfo) -> Color {
        if info.state == .charging || info.state == .recharging || info.state == .full {
            return .green
        }
        switch info.level {
        case .full, .good: return .green
        case .low: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }

    private var statusColor: Color {
        if model.isReconnecting { return .orange }
        return model.isConnected ? .green : .red
    }
}
