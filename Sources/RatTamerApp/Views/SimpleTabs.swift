import AppKit
import SwiftUI

struct AboutTabView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .cornerRadius(35)
            }
            Text("RatTamer").font(.title)
            Text("Version \(version)")
            Text("Native replacement for Logitech Options+ for the MX Master 2S.")
            Text("Buttons are captured via HID++ divert and remapped. Native behavior is restored when the app quits.")
            Text("Run without Logitech Options installed.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.9.0"
    }
}
