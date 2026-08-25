import SwiftUI

/// Standalone preview of all three button styles side by side.
/// Run: swift run RaTest --preview-styles
struct StylePreviewView: View {
    @State private var selected = "Pill"

    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Button Styles")
                .font(.title3.weight(.semibold))

            // MARK: - Pill (primary filled capsule)
            RatSectionCard(title: "Pill — Primary") {
                HStack(spacing: 10) {
                    Button("Run") { }
                        .buttonStyle(.plain)
                    Button("Ratchet") { }
                        .buttonStyle(.plain)
                    Button("Free-spin") { }
                        .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }

            // MARK: - Ghost pill (translucent bordered)
            RatSectionCard(title: "Ghost Pill — Secondary") {
                HStack(spacing: 10) {
                    Button("Back") { }
                        .buttonStyle(.plain)
                    Button("Cancel") { }
                        .buttonStyle(.plain)
                    Button("Settings") { }
                        .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }

            // MARK: - Minimal (borderless toolbar)
            RatSectionCard(title: "Minimal — Toolbar") {
                HStack(spacing: 10) {
                    Button("+") { }
                        .buttonStyle(.plain)
                    Button("−") { }
                        .buttonStyle(.plain)
                    Button("↻") { }
                        .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }

            // MARK: - Mixed row (realistic usage)
            RatSectionCard(title: "Mixed — Realistic Layout") {
                HStack(spacing: 10) {
                    Button("Cycle DPI") { }
                        .buttonStyle(.plain)
                    Button("Ratchet") { }
                        .buttonStyle(.plain)
                    Button("Free-spin") { }
                        .buttonStyle(.plain)
                    Spacer()
                    Button("+") { }
                        .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    StylePreviewView()
}
