import AppKit
import Darwin

private func rattamerSignalHandler(_ sig: Int32) {
    CrashReporter.signalFired(sig)
}

enum CrashReporter {
    private static var fd: Int32 = -1
    private static var heartbeat = Date()
    private static var hanging = false
    private static let heartbeatLock = NSLock()

    private static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("RatTamer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ratlog.log")
    }

    static func install() {
        prepareLogFile()
        writeHeader()
        NSSetUncaughtExceptionHandler(exceptionHandler)
        installSignalHandlers()
        startMainThreadPokeTimer()
        startHangWatchdog()
        addBreadcrumb("app launched")
        warnIfPreviousCrash()
    }

    // MARK: - Breadcrumbs

    static func addBreadcrumb(_ message: String) {
        writeAsync("\(stamp()) \(message)\n")
    }

    // MARK: - Crash handlers

    private static let exceptionHandler: @convention(c) (NSException) -> Void = { exception in
        CrashReporter.writeAsync("═══ CRASH uncaught exception \(exception.name.rawValue): \(exception.reason ?? "nil") ═══\n")
        for symbol in exception.callStackSymbols {
            CrashReporter.writeAsync("  \(symbol)\n")
        }
    }

    static func signalFired(_ sig: Int32) {
        var bt = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
        let count = backtrace(&bt, 128)
        let name = String(cString: strsignal(sig))
        writeAsync("═══ CRASH signal \(sig) (\(name)) at \(stamp()) ═══\n")
        backtrace_symbols_fd(&bt, Int32(count), fd)
        writeAsync("\n═══ END CRASH \(sig) ═══\n")
        signal(sig, SIG_DFL)
        raise(sig)
    }

    private static func installSignalHandlers() {
        var sa = sigaction()
        sa.sa_flags = SA_RESETHAND
        sigemptyset(&sa.sa_mask)
        sa.__sigaction_u.__sa_handler = rattamerSignalHandler
        for sig in [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGSYS, SIGTRAP] {
            sigaction(sig, &sa, nil)
        }
    }

    // MARK: - Hang watchdog

    private static func startMainThreadPokeTimer() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            heartbeatLock.lock()
            heartbeat = Date()
            heartbeatLock.unlock()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func startHangWatchdog() {
        let queue = DispatchQueue(label: "rattamer.hangwatchdog", qos: .utility)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 1.0)
        source.setEventHandler {
            let now = Date()
            heartbeatLock.lock()
            let stale = now.timeIntervalSince(heartbeat)
            heartbeatLock.unlock()
            if stale > 3.0 {
                if !hanging {
                    hanging = true
                    writeAsync("⚠️ main thread unresponsive for \(String(format: "%.1f", stale))s\n")
                }
            } else if hanging {
                hanging = false
                writeAsync("✅ main thread responsive again\n")
            }
        }
        source.resume()
    }

    // MARK: - File plumbing

    private static func prepareLogFile() {
        let url = logURL
        fd = open(url.path, O_APPEND | O_CREAT | O_WRONLY, 0o644)
    }

    private static func writeHeader() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        writeAsync("═══ RatTamer \(version) (\(build)) | macOS \(os) | first line of this session ═══\n")
    }

    private static func stamp() -> String {
        String(format: "%.3f", Date().timeIntervalSince1970)
    }

    private static func writeAsync(_ s: String) {
        guard fd >= 0 else { return }
        let bytes = Array(s.utf8)
        bytes.withUnsafeBytes { buf in
            _ = Darwin.write(fd, buf.baseAddress, buf.count)
        }
    }

    private static func warnIfPreviousCrash() {
        guard let handle = FileHandle(forReadingAtPath: logURL.path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let length = handle.offsetInFile
        let window = 4000
        let start = max(0, Int(length) - window)
        handle.seek(toFileOffset: UInt64(start))
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("═══ CRASH") {
            print("RatTamer: previous run crashed — see \(logURL.path)")
        }
    }
}
