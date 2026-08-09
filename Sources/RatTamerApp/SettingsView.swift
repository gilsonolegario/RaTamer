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
                Label("Pro", systemImage: "sparkles").tag("Pro")
                Label("About", systemImage: "info.circle").tag("About")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            switch selection {
            case "General": GeneralTabView()
            case "About": AboutTabView()
            case "Pro": ProTabView()
            default: ButtonsTabView()
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 460, idealHeight: 560)
        .onChange(of: selection) { _, newValue in
            onTitleChange(newValue)
        }
    }
}
