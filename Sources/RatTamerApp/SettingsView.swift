import SwiftUI

struct SettingsView: View {
    @AppStorage("rattamer.selectedPane") private var selection = "General"
    var onTitleChange: (String) -> Void

    init(onTitleChange: @escaping (String) -> Void) {
        self.onTitleChange = onTitleChange
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

            Group {
                switch selection {
                case "Buttons": ButtonsTabView()
                case "Scrolling": WheelScrollTabView()
                case "About": AboutTabView()
                default: GeneralTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 500)
        .onAppear {
            // Pre-1.1 panes ("Advanced") no longer exist; fall back to General
            // so the segmented picker never shows an empty selection.
            if !["General", "Buttons", "Scrolling", "About"].contains(selection) {
                selection = "General"
            }
            onTitleChange(selection)
        }
        .onChange(of: selection) { _, newValue in
            CrashReporter.addBreadcrumb("settings tab: \(newValue)")
            onTitleChange(newValue)
        }
    }
}
