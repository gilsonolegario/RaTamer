import Foundation

/// Reads and sets the system output volume through osascript. The command
/// runner is injectable so tests never touch the real audio stack.
public enum SystemVolume {
    /// Runs a `osascript -e` script and returns trimmed stdout, or nil on error.
    public static var commandRunner: (String) -> String? = runOSAScript

    public static func current() -> Int? {
        guard let out = commandRunner("output volume of (get volume settings)") else { return nil }
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func set(_ value: Int) {
        let clamped = min(100, max(0, value))
        _ = commandRunner("set volume output volume \(clamped)")
    }

    private static func runOSAScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
