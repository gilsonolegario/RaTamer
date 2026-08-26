import AppKit
import RaTamerCore
import SwiftUI

struct RaTestView: View {
    let engine: RaTestEngine
    var onContentHeight: (CGFloat) -> Void = { _ in }

    // Three tabs cover everything the old single-scroll view had:
    // Buttons, Smooth Scroll, and Hardware (Wheel Mode + DPI + Thumb Wheel).
    @AppStorage("ratest.selectedTab") private var selection = "Buttons"

    private let tabs = ["Buttons", "Scrolling", "Hardware"]

    // Last known content height of each tab. All panes stay alive in the
    // ZStack, so each records its height continuously; switching tabs
    // replays the incoming pane's recorded height immediately — a plain
    // opacity swap produces NO new layout pass, hence no fresh geometry
    // emission, so without this replay the window would never resize.
    @State private var contentHeights: [String: CGFloat] = [:]
    // Height of the tab strip itself, including its top padding. Lives
    // INSIDE the window's content but OUTSIDE each pane's measurement,
    // so the resize target is paneHeight + tabBarHeight (chrome is added
    // by RaTestWindow). Measured, not hardcoded.
    @State private var tabBarHeight: CGFloat = 0

    @State private var config: Config
    @State private var status = ""
    @State private var controls: [ControlInfo] = []
    @State private var pressed = Set<UInt16>()
    @State private var smoothEnabled = false
    @State private var maxBoost: Double = SmoothnessLevel.maxBoost(SmoothnessLevel.defaultValue)
    @State private var momentumDecay: Double = SmoothnessLevel.momentumDecay(SmoothnessLevel.defaultValue)
    @State private var momentumEnabled: Bool = SmoothnessLevel.momentumEnabled(SmoothnessLevel.defaultValue)
    @State private var pixelsPerNotch: Double = SmoothnessLevel.pixelsPerNotch(SmoothnessLevel.defaultValue)
    @State private var accelerationWindow: Double = ScrollSmoother.defaultAccelerationWindow
    @State private var feedGapTimeout: Double = ScrollSmoother.defaultFeedGapTimeout
    @State private var momentumStopThreshold: Double = ScrollSmoother.defaultMomentumStopThreshold
    @State private var bounceWindow: Double = ScrollSmoother.defaultBounceWindow
    @State private var bounceRatio: Double = ScrollSmoother.defaultBounceRatio
    @State private var bounceDamping: Double = ScrollSmoother.defaultBounceDamping
    @State private var reversalConfirmation: Int = ScrollSmoother.defaultReversalConfirmation
    @State private var directionThreshold: Double = ScrollSmoother.defaultDirectionThreshold
    @State private var smoothingEnabled: Bool = SmoothnessLevel.smoothingEnabled(SmoothnessLevel.defaultValue)
    @State private var smoothFraction: Double = SmoothnessLevel.smoothFraction(SmoothnessLevel.defaultValue)
    @State private var glideStopThreshold: Double = SmoothnessLevel.glideStopThreshold(SmoothnessLevel.defaultValue)
    @State private var syncedLevel: Double?
    @State private var selectedPreset: SmoothnessPreset = .native
    @State private var thumbWheelLog: [String] = []

    init(engine: RaTestEngine, onContentHeight: @escaping (CGFloat) -> Void = { _ in }) {
        self.engine = engine
        self.onContentHeight = onContentHeight
        _config = State(initialValue: engine.configStore.load())
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
                let padded = height + 10  // the .padding(.top) above
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
                selection = "Buttons"
            }
            startEngineHooks()
        }
        .onChange(of: selection) { _, _ in
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
                case "Buttons": buttonsContent
                case "Scrolling": scrollingContent
                case "Hardware": hardwareContent
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // No extra bottom padding here: every pane already carries its own
            // .padding(14) on all sides — stacking both inflated the measured
            // height by 14pt and the window stopped taller than the chrome.
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
        // and the pane always stopped short of the last row.
        .contentMargins(.vertical, 0, for: .scrollContent)
    }

    // MARK: - Tab panes

    private var statusText: String? {
        status.isEmpty ? nil : status
    }

    private func startEngineHooks() {
        engine.onStatus = { status = $0 }
        engine.onControlsChanged = { controls = $0 }
        engine.onPress = { cid in DispatchQueue.main.async { pressed.insert(cid) } }
        engine.onRelease = { cid in DispatchQueue.main.async { pressed.remove(cid) } }
        engine.onThumbWheel = { direction in
            DispatchQueue.main.async {
                let label = direction == .left ? "left" : "right"
                thumbWheelLog.append(label)
                if thumbWheelLog.count > 20 { thumbWheelLog.removeFirst(thumbWheelLog.count - 20) }
            }
        }
        _ = engine.start()
    }

    private var buttonsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let statusText {
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(Color.ratAccent)
                    .padding(.vertical, 4)
            }

            RatCard {
                SectionHeader(title: "Buttons")
                VStack(spacing: 6) {
                    ForEach(controls, id: \.cid) { control in
                        row(for: control)
                    }
                }
                Text(footerText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private var scrollingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            RatCard {
                SectionHeader(title: "Smooth Scroll")
                smoothPanel
            }
        }
        .padding(14)
    }

    private var hardwareContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            RatCard {
                SectionHeader(title: "Wheel Mode")
                wheelModePanel
            }

            RatCard {
                SectionHeader(title: "DPI")
                dpiPanel
            }

            RatCard {
                SectionHeader(title: "Thumb Wheel")
                thumbWheelPanel
            }
        }
        .padding(14)
    }

    private func row(for control: ControlInfo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon(for: control))
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(ControlTaskName.name(for: control.taskID))
                .frame(width: 170, alignment: .leading)
            Text(String(format: "0x%04X", control.cid))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(String(format: "tid 0x%04X", control.taskID))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
            if control.isDivertable {
                actionMenu(for: control)
                SegmentedPillRow(segments: [
                    ("Run", { engine.runAction(for: control.cid) }, !isDisabled(for: control))
                ])
                .fixedSize()
            } else {
                Text("Native only").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        // Same pressed highlight as RaTamer's ButtonsTabView rows.
        .background(pressed.contains(control.cid) ? Color.ratAccent.opacity(0.35) : Color.clear)
        .cornerRadius(6)
    }

    /// SF Symbol matching the control's task ID — same mapping as RaTamer.
    private func icon(for control: ControlInfo) -> String {
        switch control.taskID {
        case 0x0038: return "cursorarrow"
        case 0x0039: return "arrow.up.right"
        case 0x003A: return "circle.fill"
        case 0x003C: return "arrow.left.to.line"
        case 0x003E: return "arrow.right.to.line"
        case 0x009D: return "scroll"
        case 0x00A9: return "hand.draw"
        case ControlCID.virtualGesture: return "wand.and.stars"
        default: return "questionmark.circle"
        }
    }

    /// Menu with the same custom label as RaTamer (text + chevron on a gray
    /// pill) — the native `.pickerStyle(.menu)` pop-up looks dated next to it.
    private func actionMenu(for control: ControlInfo) -> some View {
        let action = config.action(forCID: control.cid) ?? .disabled
        return Menu {
            // Inline picker inside the menu keeps the actionBinding intact
            // while rendering as native check-marked items.
            Picker("", selection: actionBinding(for: control)) {
                actionOptions
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: ActionCatalog.icon(for: action))
                Text(ActionCatalog.title(for: action))
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.15)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func actionBinding(for control: ControlInfo) -> Binding<ButtonAction> {
        Binding(
            get: { config.action(forCID: control.cid) ?? .disabled },
            set: { newValue in
                config.setAction(newValue, forCID: control.cid)
                try? engine.configStore.save(config)
            }
        )
    }

    private func isDisabled(for control: ControlInfo) -> Bool {
        let action = config.action(forCID: control.cid)
        return action == nil || action == .disabled
    }

    private var footerText: String {
        if pressed.isEmpty {
            return "Press a physical button to identify it."
        }
        let names = pressed.map { cid -> String in
            let info = controls.first { $0.cid == cid }
            let name = info.map { ControlTaskName.name(for: $0.taskID) } ?? String(format: "0x%04X", cid)
            return "\(name) (0x\(String(format: "%04X", cid)))"
        }.sorted()
        return "Pressed: " + names.joined(separator: ", ")
    }

    private var actionOptions: some View {
        ForEach(ActionCatalog.allActions, id: \.self) { action in
            Text(ActionCatalog.title(for: action)).tag(action)
        }
    }

    private var smoothPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enabled (diverts wheel to HID++)", isOn: $smoothEnabled)
                .onChange(of: smoothEnabled) { _, _ in applySmoothEnable() }
            Text("Multiplier: \(engine.wheelMultiplier ?? 8)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Level").frame(width: 160, alignment: .leading)
                Slider(value: levelBinding, in: 0...100, step: 1)
                Text(levelLabel).font(.caption.monospaced()).frame(width: 56, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text("Presets").frame(width: 160, alignment: .leading)
                SegmentedPillPicker(
                    items: SmoothnessPreset.allCases,
                    selection: $selectedPreset,
                    label: { $0.displayName }
                )
                .onChange(of: selectedPreset) { _, newPreset in
                    applyPreset(newPreset)
                }
            }
            sliderRow("Max boost", value: $maxBoost, range: 1.0...6.0, step: 0.1)
            sliderRow("Momentum decay", value: $momentumDecay, range: 0.5...0.98, step: 0.01)
            Toggle("Momentum", isOn: $momentumEnabled)
                .onChange(of: momentumEnabled) { _, _ in applySmoothParams() }
            Toggle("Smoothing (glide)", isOn: $smoothingEnabled)
                .onChange(of: smoothingEnabled) { _, _ in applySmoothParams() }
            sliderRow("Smooth fraction", value: $smoothFraction, range: 0.02...0.15, step: 0.01)
            sliderRow("Glide stop", value: $glideStopThreshold, range: 0.0...2.0, step: 0.1)
            sliderRow("Pixels per notch", value: $pixelsPerNotch, range: 1...200, step: 1)
            DisclosureGroup("Advanced tuning") {
                VStack(alignment: .leading, spacing: 8) {
                    sliderRow("Accel window (s)", value: $accelerationWindow, range: 0.01...0.20, step: 0.01)
                    sliderRow("Feed gap timeout (s)", value: $feedGapTimeout, range: 0.02...0.30, step: 0.01)
                    sliderRow("Momentum stop", value: $momentumStopThreshold, range: 0.0...1.0, step: 0.05)
                    sliderRow("Bounce window (s)", value: $bounceWindow, range: 0.0...0.20, step: 0.005)
                    sliderRow("Bounce ratio", value: $bounceRatio, range: 0.1...1.0, step: 0.05)
                    sliderRow("Bounce damping", value: $bounceDamping, range: 0.0...1.0, step: 0.05)
                    Stepper("Reversal confirmation: \(reversalConfirmation)",
                            value: $reversalConfirmation, in: 1...5)
                        .onChange(of: reversalConfirmation) { _, _ in applySmoothParams() }
                    sliderRow("Direction threshold", value: $directionThreshold, range: 0.0...5.0, step: 0.25)
                }
                .padding(.top, 6)
            }
        }
    }

    private var wheelModePanel: some View {
        Group {
            if engine.hasSmartShift {
                HStack {
                    Text("Mode: \(engine.wheelModeDescription)")
                        .frame(width: 200, alignment: .leading)
                    SegmentedPillRow(segments: [
                        ("Ratchet", { engine.setWheelMode(ratcheted: true) }, engine.wheelModeDescription == "Ratchet"),
                        ("Free-spin", { engine.setWheelMode(ratcheted: false) }, engine.wheelModeDescription != "Ratchet")
                    ])
                    .fixedSize()
                    Spacer()
                }
            } else {
                Text("Device has no SmartShift.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dpiPanel: some View {
        HStack {
            Text("Current: \(engine.currentDPI.map(String.init) ?? "—")")
                .frame(width: 200, alignment: .leading)
            Text("Cycle: \(engine.dpiCycleValues.map(String.init).joined(separator: " → "))")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
            SegmentedPillRow(segments: [
                ("Cycle DPI", { engine.cycleDPI() }, !engine.dpiCycleValues.isEmpty)
            ])
            Spacer()
        }
    }

    private var thumbWheelPanel: some View {
        HStack {
            Text(thumbWheelLog.isEmpty
                 ? "Spin the thumb wheel."
                 : "Notches: " + thumbWheelLog.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(thumbWheelLog.isEmpty ? .secondary : .primary)
            Spacer()
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).frame(width: 160, alignment: .leading)
            Slider(value: value, in: range, step: step) { editing in
                if !editing, syncedLevel != nil { syncedLevel = nil }
            }
            .onChange(of: value.wrappedValue) { _, _ in applySmoothParams() }
            Text(String(format: "%.3f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var levelBinding: Binding<Double> {
        Binding(
            get: {
                if let syncedLevel { return syncedLevel }
                return SmoothnessLevel.defaultValue
            },
            set: { applyLevel($0) }
        )
    }

    private var levelLabel: String {
        if let syncedLevel { return String(format: "%.0f", syncedLevel) }
        return "custom"
    }

    private func applyPreset(_ preset: SmoothnessPreset) {
        if preset == .native {
            smoothEnabled = false
            return
        }
        applyLevel(preset.level)
    }

    private func applyLevel(_ level: Double) {
        syncedLevel = level
        let p = SmoothnessLevel.parameters(level: level,
                                           multiplier: engine.wheelMultiplier ?? 8,
                                           invert: false)
        maxBoost = p.maxBoost
        momentumDecay = p.momentumDecay
        momentumEnabled = p.momentumEnabled
        smoothingEnabled = p.smoothingEnabled
        pixelsPerNotch = p.pixelsPerNotch
        smoothFraction = p.smoothFraction
        glideStopThreshold = p.glideStopThreshold
        applySmoothParams()
    }

    private var currentParams: ScrollSmoother.Parameters {
        ScrollSmoother.Parameters(
            multiplier: engine.wheelMultiplier ?? 8,
            momentumEnabled: momentumEnabled,
            invert: false,
            maxBoost: maxBoost,
            momentumDecay: momentumDecay,
            pixelsPerNotch: pixelsPerNotch,
            accelerationWindow: accelerationWindow,
            feedGapTimeout: feedGapTimeout,
            momentumStopThreshold: momentumStopThreshold,
            bounceWindow: bounceWindow,
            bounceRatio: bounceRatio,
            bounceDamping: bounceDamping,
            reversalConfirmation: reversalConfirmation,
            directionThreshold: directionThreshold,
            smoothingEnabled: smoothingEnabled,
            smoothFraction: smoothFraction,
            glideStopThreshold: glideStopThreshold)
    }

    private func applySmoothEnable() {
        engine.setSmoothScroll(enabled: smoothEnabled, parameters: currentParams)
    }

    private func applySmoothParams() {
        engine.setSmoothParameters(currentParams)
    }
}
