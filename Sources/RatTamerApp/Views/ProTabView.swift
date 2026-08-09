import AppKit
import RatTamerCore
import SwiftUI

enum ProStore {
    static let productURL = URL(string: "https://rattamer.gumroad.com/l/\(LicenseService.productID)")!
}

struct ProTabView: View {
    @ObservedObject private var model = AppModel.shared
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RatTamer Pro").font(.headline)
            statusView
            Divider()
            Text("Pro features: Gestures, SmartShift, Run Shortcut, Smooth Scrolling, multiple profiles.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            key = model.license.storedKey ?? ""
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.licenseState {
        case .active:
            Label("Pro is active", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Button("Remove license") { model.license.clear() }
                .controlSize(.small)
        case .unlicensed, .invalid, .offlineExpired:
            TextField("License key", text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            HStack {
                Button("Activate") {
                    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task { await model.license.submit(key: trimmed) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let url = ProStore.productURL as URL? {
                    Button("Get RatTamer Pro →") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .validating:
            ProgressView("Checking license…")
                .controlSize(.small)
        }
    }
}
