import SwiftUI
import RatTamerCore

struct MenuBarPopoverView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var battery = BatteryMonitor.shared
    @ObservedObject private var loginItem = LoginItem.shared
    @State private var hoveredRow: String?
    @State private var volume: Double = 50
    @State private var volumeLoaded = false

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

            volumeRow

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
                NSApp.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 280)
        .onAppear {
            BatteryMonitor.shared.start()
            loadVolume()
        }
        .onDisappear { BatteryMonitor.shared.stop() }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    private var volumeRow: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("Volume")
                    .font(.callout)
                Spacer()
                Text("\(Int(volume))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $volume, in: 0...100, step: 1) { editing in
                if !editing { applyVolume() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func loadVolume() {
        volumeLoaded = false
        volume = Double(SystemVolume.current() ?? 50)
        volumeLoaded = true
    }

    private func applyVolume() {
        guard volumeLoaded else { return }
        SystemVolume.set(Int(volume))
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
        if model.isReconnecting { return .orange }
        return model.isConnected ? .green : .red
    }
}
