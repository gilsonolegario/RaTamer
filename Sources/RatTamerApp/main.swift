import AppKit

CrashReporter.install()

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
