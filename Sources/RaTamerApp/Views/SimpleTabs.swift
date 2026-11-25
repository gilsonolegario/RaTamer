import AppKit
import RaTamerCore
import SwiftUI

struct AboutTabView: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RatCard {
                HStack(spacing: 16) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("RaTamer")
                                .font(.title2.weight(.bold))
                            Text(verbatim: "v\(version)")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                        Text("Native replacement for Logitech Options+ over HID++ 2.0.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Controls are captured via HID++ divert and restored automatically on quit.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }

            RatSectionCard(title: "Hardware") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Device")
                        Spacer()
                        Text(model.isConnected ? model.deviceName : "Not connected")
                            .foregroundStyle(.secondary)
                    }
                    Divider().opacity(0.4)
                    HStack {
                        Text("Controls")
                        Spacer()
                        Text(model.isConnected ? "\(model.controls.count) detected" : "—")
                            .foregroundStyle(.secondary)
                    }
                    Divider().opacity(0.4)
                    BatteryStatusRow()
                }
            }

            RatSectionCard(title: "Tools") {
                HStack(spacing: 8) {
                    SegmentedPillRow(segments: [
                        (label: "Show Welcome Guide…", action: { OnboardingWindow.shared.show() }, isHighlighted: false),
                        (label: "Scroll Thermograph…", action: { ScrollGraphWindow.shared.show() }, isHighlighted: false),
                        (label: "Reveal Config", action: {
                            NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.defaultFileURL()])
                        }, isHighlighted: false),
                    ], compact: true)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.7"
    }
}

/// Moved from GeneralTabView — device status belongs in About.
struct BatteryStatusRow: View {
    @ObservedObject private var battery = BatteryMonitor.shared
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        HStack {
            Text("Battery")
            Spacer()
            if let info = battery.info {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: info))
                        .frame(width: 8, height: 8)
                    Text(BatteryDisplay.title(for: info).replacingOccurrences(of: "Battery: ", with: ""))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(model.isConnected ? "Unavailable on this device" : "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            BatteryMonitor.shared.refresh()
        }
    }

    private func color(for info: BatteryInfo) -> Color {
        if info.state == .full || info.state == .charging || info.state == .recharging {
            return .green
        }
        switch info.level {
        case .full: return .green
        case .good: return .yellow
        case .low: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}
