import AppKit
import RaTamerCore
import SwiftUI

struct AboutTabView: View {
    @ObservedObject private var model = AppModel.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 96, height: 96)
                            .cornerRadius(21)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RaTamer").font(.title2).fontWeight(.bold)
                        Text("Version \(version)")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Native replacement for Logitech Options+ for the \(model.deviceName).")
                Text("Buttons are captured via HID++ divert and remapped. Native behavior is restored when the app quits.")
                Text("Run without Logitech Options installed.")
                Divider()
                Text("Hardware")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Device")
                    Spacer()
                    Text(model.deviceName)
                        .foregroundStyle(.secondary)
                }
                BatteryStatusRow()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

/// Moved from GeneralTabView — device status belongs in About.
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
