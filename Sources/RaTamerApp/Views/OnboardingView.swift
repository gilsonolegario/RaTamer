import SwiftUI
import RaTamerCore

struct OnboardingView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var loginItem = LoginItem.shared
    var onFinish: () -> Void

    var body: some View {
        let accessibility = model.accessibilityTrusted
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "computermouse.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome to RaTamer")
                            .font(.title2.bold())
                        Text("Remap your Logitech MX buttons, gestures, smooth scroll, and thumb wheel.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            VStack(alignment: .leading, spacing: 16) {
                stepRow(
                    number: "1",
                    icon: connectionOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    iconColor: connectionOK ? .green : .orange,
                    title: "Connect your mouse",
                    detail: model.statusText
                )
                stepRow(
                    number: "2",
                    icon: accessibility ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: accessibility ? .green : .orange,
                    title: "Grant Accessibility",
                    detail: accessibility
                        ? "RaTamer can remap buttons and post keys."
                        : "Required to send button, shortcut and gesture events."
                )
                if !accessibility {
                    Button("Open System Settings…") {
                        Permissions.requestAccessibility()
                        model.refreshAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.leading, 40)
                }
                stepRow(
                    number: "3",
                    icon: "power.circle.fill",
                    iconColor: .blue,
                    title: "Run at login",
                    detail: "Keep remapping available after a restart."
                )
                Toggle("Start at login", isOn: $loginItem.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .padding(.leading, 40)
            }
            .padding(20)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            HStack {
                Spacer()
                Button("Get Started") {
                    OnboardingGate.complete()
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 500)
        .onAppear { model.refreshAccessibility() }
    }

    private var connectionOK: Bool {
        model.isConnected
    }

    private func stepRow(number: String, icon: String, iconColor: Color,
                         title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.07)).frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
