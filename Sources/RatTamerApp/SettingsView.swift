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
                Label("Advanced", systemImage: "slider.horizontal.3").tag("Advanced")
                Label("About", systemImage: "info.circle").tag("About")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Group {
                switch selection {
                case "General": GeneralTabView()
                case "Advanced": AdvancedTabView()
                case "About": AboutTabView()
                default: ButtonsTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 700, idealWidth: 780, minHeight: 560, idealHeight: 620)
        .onChange(of: selection) { _, newValue in
            CrashReporter.addBreadcrumb("settings tab: \(newValue)")
            onTitleChange(newValue)
        }
    }
}
