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
            Picker("", selection: $selection) {
                Label("General", systemImage: "gearshape").tag("General")
                Label("Buttons", systemImage: "computermouse").tag("Buttons")
                Label("Scrolling", systemImage: "scroll").tag("Scrolling")
                Label("About", systemImage: "info.circle").tag("About")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
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
                // Continuous geometry callback (back-deployed); PreferenceKey
                // + GeometryReader proved one-shot here: it fired only on the
                // first layout and never on pane switches.
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
            // Pre-1.1 panes ("Advanced") no longer exist; fall back to General
            // so the segmented picker never shows an empty selection.
            if !["General", "Buttons", "Scrolling", "About"].contains(selection) {
                selection = "General"
            }
            // Async: on first open the SwiftUI view lays out while
            // NSWindow(contentViewController:) is still initializing, before
            // SettingsWindow.window is assigned — the sync callback would hit nil.
            DispatchQueue.main.async { self.onTitleChange(selection) }
        }
        .onChange(of: selection) { _, newValue in
            CrashReporter.addBreadcrumb("settings tab: \(newValue)")
            onTitleChange(newValue)
        }
    }
}
