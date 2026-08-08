import RatTamerCore

enum ActionCatalog {
    static func title(for action: ButtonAction) -> String {
        switch action {
        case .disabled: return "Native (default)"
        case .shortcut(let key, let modifiers):
            return "Shortcut \(shortcutDisplay(key: key, modifiers: modifiers))"
        case .runShortcut(let name):
            return "Run Shortcut: \(name)"
        case .system(let name):
            return systemTitle(name)
        case .click(let button):
            return button == 4 ? "Forward Click" : "Back Click"
        case .gesture: return "Gesture"
        case .cycleDPI: return "Cycle DPI"
        }
    }

    static func icon(for action: ButtonAction) -> String {
        switch action {
        case .disabled: return "circle.slash"
        case .shortcut: return "keyboard"
        case .runShortcut: return "applescript"
        case .system(let name): return systemIcon(name)
        case .click(let button):
            return button == 4 ? "arrow.right.to.line" : "arrow.left.to.line"
        case .gesture: return "hand.draw"
        case .cycleDPI: return "speedometer"
        }
    }

    static func systemTitle(_ name: String) -> String {
        switch name {
        case "missionControl": return "Mission Control"
        case "appExpose": return "App Expose"
        case "showDesktop": return "Show Desktop"
        case "launchpad": return "Launchpad"
        case "previousSpace": return "Previous Space"
        case "nextSpace": return "Next Space"
        case "spotlight": return "Spotlight"
        case "lockScreen": return "Lock Screen"
        case "volumeUp": return "Volume Up"
        case "volumeDown": return "Volume Down"
        case "volumeUpSmall": return "Volume Up (small)"
        case "volumeDownSmall": return "Volume Down (small)"
        case "volumeMute": return "Mute"
        default: return name
        }
    }

    static func systemIcon(_ name: String) -> String {
        switch name {
        case "missionControl", "appExpose": return "rectangle.3.group"
        case "showDesktop": return "rectangle.split.2x1"
        case "launchpad": return "square.grid.3x3"
        case "previousSpace": return "arrow.left"
        case "nextSpace": return "arrow.right"
        case "spotlight": return "magnifyingglass"
        case "lockScreen": return "lock"
        case "volumeUp": return "speaker.wave.2"
        case "volumeDown": return "speaker.wave.1"
        case "volumeUpSmall": return "speaker.wave.2"
        case "volumeDownSmall": return "speaker.wave.1"
        case "volumeMute": return "speaker.slash"
        default: return "bolt"
        }
    }

    static func shortcutDisplay(key: String, modifiers: [String]) -> String {
        var result = ""
        let symbols: [(String, String)] = [
            ("control", "⌃"), ("option", "⌥"), ("shift", "⇧"), ("command", "⌘"),
        ]
        for (name, symbol) in symbols where modifiers.contains(name) {
            result += symbol
        }
        result += key.capitalized
        return result
    }
}
