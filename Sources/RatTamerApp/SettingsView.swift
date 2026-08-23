import SwiftUI

struct SettingsView: View {
    @AppStorage("rattamer.selectedPane") private var selection = "General"
    var onTitleChange: (String) -> Void

    init(onTitleChange: @escaping (String) -> Void) {
        self.onTitleChange = onTitleChange
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag("General")
                Label("Buttons", systemImage: "computermouse").tag("Buttons")
                Label("Advanced", systemImage: "slider.horizontal.3").tag("Advanced")
                Label("About", systemImage: "info.circle").tag("About")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            switch selection {
            case "General": GeneralTabView()
            case "Advanced": AdvancedTabView()
            case "About": AboutTabView()
            default: ButtonsTabView()
            }
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 620, idealHeight: 800)
        .onChange(of: selection) { _, newValue in
            CrashReporter.addBreadcrumb("settings tab: \(newValue)")
            onTitleChange(newValue)
        }
    }
}
