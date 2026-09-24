import Foundation
import UIKit
import UserNotifications

/// Manages APNs push notification authorization, device token registration,
/// and incoming notification routing (Moment 1 — Wake / Morning verdict).
@MainActor
@Observable
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    var deviceToken: String?
    var isAuthorized: Bool = false
    private(set) var lastRegisteredToken: String?

    /// Queued navigation action when a push notification is opened.
    var pendingTabSelection: ShellTab?

    init() {}

    /// Requests user authorization for alerts, badges, and sounds,
    /// then registers for remote notifications with APNs.
    func requestAuthorization() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                self.isAuthorized = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                return granted
            } else {
                let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                self.isAuthorized = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                return granted
            }
        } catch {
            return false
        }
    }

    /// Stores the hex device token received from APNs.
    func didRegisterForRemoteNotifications(with deviceTokenData: Data) {
        let hexString = deviceTokenData.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = hexString
    }

    /// Registers the device token with the server if available and not yet synced.
    func syncDeviceTokenIfNeeded(
        tokenProvider: () async throws -> String,
        client: PushDeviceTokenServing = SharpitClient()
    ) async {
        guard let deviceToken, deviceToken != lastRegisteredToken else { return }
        do {
            let authToken = try await tokenProvider()
            #if DEBUG
            let isDebug = true
            #else
            let isDebug = false
            #endif
            try await client.registerDeviceToken(deviceToken, debug: isDebug, token: authToken)
            self.lastRegisteredToken = deviceToken
        } catch {
            // Fails silently; will retry on next app foreground / launch
        }
    }

    /// Handles a notification response (e.g. tap on morning verdict notification).
    func didReceiveNotificationResponse(userInfo: [AnyHashable: Any]) {
        let category = userInfo["category"] as? String
            ?? (userInfo["aps"] as? [String: Any])?["category"] as? String
        let threadId = (userInfo["aps"] as? [String: Any])?["thread-id"] as? String
        let urlString = userInfo["url"] as? String

        if category == "MORNING_VERDICT" || threadId == "morning-verdict" {
            self.pendingTabSelection = .today
        } else if let urlString, let url = URL(string: urlString) {
            switch url.path {
            case "/today":
                self.pendingTabSelection = .today
            case "/plan":
                self.pendingTabSelection = .plan
            case "/coach":
                self.pendingTabSelection = .coach
            case "/activity", "/activities":
                self.pendingTabSelection = .activity
            case "/me", "/profile", "/settings":
                self.pendingTabSelection = .me
            default:
                break
            }
        }
    }

    /// Consumes the pending navigation action if any.
    func consumePendingNavigation() -> ShellTab? {
        let tab = pendingTabSelection
        pendingTabSelection = nil
        return tab
    }
}
