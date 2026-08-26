import SwiftUI

struct SettingsView: View {
    @AppStorage("ratamer.selectedPane") private var selection = "General"
    var onContentHeight: (CGFloat) -> Void

    private let tabs = ["General", "Buttons", "Scrolling", "About"]

    // Last known content height of each tab. All panes stay alive in the
    // ZStack, so each records its height continuously; switching tabs
    // replays the incoming pane's recorded height immediately — a plain
    // opacity swap produces NO new layout pass, hence no fresh geometry
    // emission, so without this replay the window would never resize.
    @State private var contentHeights: [String: CGFloat] = [:]
    // Height of the tab strip itself. It lives INSIDE the window's content
    // view but OUTSIDE each pane's measured content, so the resize target
    // is paneHeight + tabBarHeight (+ title-bar chrome, added by
    // SettingsWindow). Measured, not hardcoded — the old "+40 magic number"
    // was secretly compensating for exactly this.
    @State private var tabBarHeight: CGFloat = 0

    init(onContentHeight: @escaping (CGFloat) -> Void) {
        self.onContentHeight = onContentHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            TabBar(
                tabs: tabs,
                selection: $selection)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                // Include the surrounding .padding(.top, 10) — the proxy
                // reports the TabBar alone, so add the padding explicitly.
                let padded = height + 10
                if padded != tabBarHeight {
                    tabBarHeight = padded
                    reportTotalHeight()
                }
            }

            // All panes stay alive — the crossfade is a pure opacity
            // transition with no teardown/recreation. The 8pt vertical drift
            // gives the incoming pane directional movement (rises into place)
            // instead of a static fade.
            ZStack(alignment: .top) {
                ForEach(tabs, id: \.self) { tab in
                    tabContent(for: tab)
                        .opacity(selection == tab ? 1 : 0)
                        .offset(y: selection == tab ? 0 : 8)
                        .allowsHitTesting(selection == tab)
                }
            }
        }
        .onAppear {
            if !tabs.contains(selection) {
                selection = "General"
            }
        }
        .onChange(of: selection) { _, newValue in
            CrashReporter.addBreadcrumb("settings tab: \(newValue)")
            reportTotalHeight()
        }
    }

    /// Reports the full content height (tab strip + visible pane) so the
    /// window can hug it exactly. Single source of truth for the resize
    /// target — every height change funnels through here.
    private func reportTotalHeight() {
        guard let paneHeight = contentHeights[selection] else { return }
        onContentHeight(paneHeight + tabBarHeight)
    }

    private func tabContent(for tab: String) -> some View {
        ScrollView {
            Group {
                switch tab {
                case "Buttons": ButtonsTabView()
                case "Scrolling": WheelScrollTabView()
                case "About": AboutTabView()
                default: GeneralTabView()
                }
            }
            .frame(maxWidth: .infinity)
            // Explicit breathing room BELOW the content, included in the
            // measurement (applied before onGeometryChange reads the size).
            .padding(.bottom, 14)
            // Measure THIS pane's content height INSIDE its ScrollView:
            // the viewport clips, the content doesn't — this reports the
            // ideal height even when it exceeds the visible area.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeights[tab] = height
                if selection == tab {
                    reportTotalHeight()
                }
            }
        }
        // Kill the automatic vertical content margins: they sit OUTSIDE the
        // measured node, so the window resize could never account for them
        // and the pane always stopped short of the last row. With margins
        // gone and padding explicit above, measured height == needed height.
        .contentMargins(.vertical, 0, for: .scrollContent)
    }
}
