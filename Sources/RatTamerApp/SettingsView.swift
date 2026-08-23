import SwiftUI

/// Reports the natural height of the active pane's content so the window
/// can resize to hug it.
struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SettingsView: View {
    @AppStorage("rattamer.selectedPane") private var selection = "General"
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
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
                .frame(maxWidth: .infinity)
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
        .onPreferenceChange(ContentHeightKey.self) { height in
            onContentHeight(height)
        }
    }
}
