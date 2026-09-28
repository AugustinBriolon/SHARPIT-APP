import UIKit
import UserNotifications

/// Tells the athlete something finished while they were elsewhere — a notification only when
/// the app is not in front (in front, the screen already shows it), and only if they allowed
/// notifications.
@MainActor
enum LocalNotifications {
    /// Plan's generator, opened by a tap on « Ta semaine est prête ».
    static let planGeneratorPath = "/plan/generator"

    static func notifyIfAway(title: String, body: String, path: String) async {
        guard UIApplication.shared.applicationState != .active else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": path]
        try? await center.add(UNNotificationRequest(identifier: path, content: content, trigger: nil))
    }
}
