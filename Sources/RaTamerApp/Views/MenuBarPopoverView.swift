import SwiftUI
import RaTamerCore

struct MenuBarPopoverView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var battery = BatteryMonitor.shared
    @ObservedObject private var loginItem = LoginItem.shared
    @State private var hoveredRow: String?
    @State private var hoveredStatus = false
    @StateObject private var statusHoverHandler = HoverTaskHandler()
    @State private var dpi: Double = 1000
    @State private var dpiValues: [UInt16] = []
    @State private var dpiLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(hoveredStatus ? 1.4 : 1)
                    .animation(.interactiveSpring, value: hoveredStatus)
                    .animation(.easeInOut(duration: 0.3), value: model.isConnected)
                Text(model.statusText)
                    .font(.callout)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredStatus ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHoverWithDebounce(delay: .milliseconds(100), handler: statusHoverHandler) { value in
                hoveredStatus = value
            }

            if let info = battery.info {
                batteryRow(for: info)
            }

            separator

            dpiRow

            separator

            toggleRow(label: "Enable remapping", isOn: $model.remappingEnabled)

            separator

            toggleRow(label: "Start at login", isOn: $loginItem.isEnabled)

            separator

            actionRow(icon: "gearshape", label: "Settings…",
                      isHovered: hoveredRow == "settings",
                      onHover: { hoveredRow = $0 ? "settings" : nil }) {
                SettingsWindow.shared.show()
            }
            actionRow(icon: "arrow.clockwise", label: "Reconnect",
                      isHovered: hoveredRow == "reconnect",
                      onHover: { hoveredRow = $0 ? "reconnect" : nil }) {
                AppModel.shared.engine?.reconnect()
            }
            actionRow(icon: "power", label: "Quit",
                      isHovered: hoveredRow == "quit",
                      onHover: { hoveredRow = $0 ? "quit" : nil }) {
                // Tear down the process-lifetime keyboard-layout observer so it
                // never outlives the engine (ActionEngine.shutdown is idempotent).
                ActionEngine.shutdown()
                NSApp.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            BatteryMonitor.shared.start()
            loadDPI()
        }
        .onDisappear {
            BatteryMonitor.shared.stop()
            statusHoverHandler.cancel()
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    private var dpiRow: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("Pointer Resolution")
                    .font(.callout)
                Spacer()
                if dpiAvailable {
                    Text("\(Int(dpi)) DPI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if dpiAvailable {
                Slider(value: Binding(get: { dpi },
                                      set: { newValue in
                                          withAnimation(.snappy(duration: 0.25)) { dpi = newValue }
                                      }),
                       in: dpiRange, step: dpiStep) { editing in
                    if !editing { applyDPI() }
                }
                .controlSize(.small)
                .tint(Color.accentColor)
                .frame(height: 22)
            } else {
                Text("DPI feature unavailable on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var dpiAvailable: Bool {
        dpiValues.count > 1
    }

    private var dpiRange: ClosedRange<Double> {
        Double(dpiValues.first ?? 0)...Double(dpiValues.last ?? 0)
    }

    private var dpiStep: Double {
        guard dpiValues.count >= 2 else { return 1 }
        let gaps = zip(dpiValues.dropFirst(), dpiValues).map { Double($0 - $1) }
        return gaps.min() ?? 1
    }

    private func loadDPI() {
        guard let service = AppModel.shared.engine?.dpiService else { return }
        let currentDPI = dpi
        DispatchQueue.global(qos: .utility).async {
            let values = (try? service.getSensorDpiList(sensor: 0)) ?? []
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
            DispatchQueue.main.async {
                self.dpiValues = values
                self.dpi = selected
                self.dpiLoaded = true
            }
        }
    }

    private func applyDPI() {
        guard dpiLoaded else { return }
        var config = AppModel.shared.configStore.load()
        config.dpiValue = UInt16(dpi)
        try? AppModel.shared.configStore.save(config)
        AppModel.shared.engine?.applyConfig()
    }

    private func batteryRow(for info: BatteryInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: BatteryDisplay.symbol(for: info))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(BatteryDisplay.title(for: info))
                .font(.callout)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private func toggleRow(label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Image(systemName: "switch.2")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.callout)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .frame(minHeight: 28, alignment: .leading)
    }

    private func actionRow(icon: String, label: String,
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
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.gray.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .styledButton(hoverScale: 1.0, pressScale: 0.96)
        .onHover(perform: onHover)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var statusColor: Color {
        if model.isReconnecting { return .orange }
        return model.isConnected ? .green : .red
    }
}
