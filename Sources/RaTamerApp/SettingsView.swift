import SwiftUI

struct SettingsView: View {
    @AppStorage("ratamer.selectedPane") private var selection = "General"
    var onTitleChange: (String) -> Void
    var onContentHeight: (CGFloat) -> Void

    init(onTitleChange: @escaping (String) -> Void,
         onContentHeight: @escaping (CGFloat) -> Void) {
        self.onTitleChange = onTitleChange
        self.onContentHeight = onContentHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            TabBar(
                tabs: ["General", "Buttons", "Scrolling", "About"],
                selection: $selection)
            .padding(.horizontal, 14)
            .padding(.top, 10)

            ScrollView {
                Group {
                    switch selection {
                    case "Buttons": ButtonsTabView()
                    case "Scrolling": WheelScrollTabView()
                    case "About": AboutTabView()
                    default: GeneralTabView()
                    }
                }
                .frame(maxWidth: .infinity)
                // Continuous geometry callback; PreferenceKey + GeometryReader
                // was one-shot here (fired only on first layout, never on pane
                // switches). onGeometryChange fires on every layout pass.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    onContentHeight(height)
                }
                // Fresh identity per pane: guarantees a new geometry emission
                // on every switch instead of relying on diffed updates.
                .id(selection)
            }
        }
        .onAppear {
            if !["General", "Buttons", "Scrolling", "About"].contains(selection) {
                selection = "General"
            }
            DispatchQueue.main.async { self.onTitleChange(selection) }
        }
        .onChange(of: selection) { _, newValue in
            CrashReporter.addBreadcrumb("settings tab: \(newValue)")
            onTitleChange(newValue)
            SettingsWindow.shared.recordTabSwitch()
        }
    }
}
