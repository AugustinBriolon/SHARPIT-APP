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

    /// The athlete's own switch, in Paramètres. iOS owns the permission and the app cannot take
    /// it back, so « off » means the server forgets this device and SharpIt stops asking — the
    /// only way to be silent without sending the athlete into iOS Settings.
    private(set) var isEnabledByAthlete: Bool

    static let enabledKey = "sharpit.notifications.enabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabledByAthlete = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// The system permission as it stands now.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Turns SharpIt's notifications on or off for this iPhone. On asks iOS when it has not been
    /// asked yet and registers the device; off unregisters it server-side. Returns whether the
    /// notifications are now actually deliverable.
    @discardableResult
    func setEnabled(
        _ enabled: Bool,
        tokenProvider: () async throws -> String,
        client: PushDeviceTokenServing = SharpitClient()
    ) async -> Bool {
        isEnabledByAthlete = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled {
            let granted = await requestAuthorization()
            if granted { await syncDeviceTokenIfNeeded(tokenProvider: tokenProvider, client: client) }
            return granted
        }
        if let registered = lastRegisteredToken ?? deviceToken,
           let authToken = try? await tokenProvider() {
            try? await client.unregisterDeviceToken(registered, token: authToken)
        }
        lastRegisteredToken = nil
        return false
    }

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
        guard isEnabledByAthlete, let deviceToken, deviceToken != lastRegisteredToken else { return }
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
            // A push's `/settings` predates the Paramètres sheet and still lands on Corps.
            if let tab = IncomingLink.tab(forPath: url.path) ?? (url.path == "/settings" ? .body : nil) {
                self.pendingTabSelection = tab
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
