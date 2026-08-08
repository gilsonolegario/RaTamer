import SwiftUI
import RatTamerCore

struct MenuBarPopoverView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var battery = BatteryMonitor.shared
    @State private var hoveredRow: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(model.statusText)
                    .font(.callout)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)

            if let info = battery.info {
                batteryRow(for: info)
            }

            separator

            toggleRow(label: "Enable remapping", isOn: $model.remappingEnabled)

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
                NSApp.terminate(nil)
            }
        }
        .padding(10)
        .fixedSize()
        .onAppear { BatteryMonitor.shared.start() }
        .onDisappear { BatteryMonitor.shared.stop() }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .frame(height: 1)
            .padding(.horizontal, 4)
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
        .onHover(perform: onHover)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var statusColor: Color {
        let connected = model.statusText.contains("Connected")
        return connected ? .green : .red
    }
}
