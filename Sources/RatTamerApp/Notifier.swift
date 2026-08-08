import Foundation
import UserNotifications

enum Notifier {
    // UNUserNotificationCenter.current() throws NSInternalInconsistencyException
    // when the process has no app bundle (e.g. `swift run` from .build).
    private static var hasBundle: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static func requestAuthorization() {
        guard hasBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard hasBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
