import AppKit
import Foundation
import ServiceManagement

final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            try? setEnabled(isEnabled)
        }
    }

    private init() {
        if SMAppService.mainApp.status == .enabled {
            isEnabled = true
        } else {
            isEnabled = LaunchAgent.isInstalled
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } else if enabled {
            try LaunchAgent.install()
        } else {
            try LaunchAgent.uninstall()
        }
    }
}

enum LaunchAgent {
    private static let label = "com.rattamer"
    private static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.rattamer.plist")

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: path.path)
    }

    static func install() throws {
        let execPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [execPath, "--background"],
            "RunAtLoad": true,
            "KeepAlive": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                      format: .xml,
                                                      options: 0)
        try data.write(to: path, options: .atomic)
    }

    static func uninstall() throws {
        try? FileManager.default.removeItem(at: path)
    }
}
