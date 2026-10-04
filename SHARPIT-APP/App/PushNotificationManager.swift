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

    /// Where the last tapped notification leads, until the shell opens it.
    var pendingDestination: NotificationDestination?

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

    /// Handles a tapped notification: remembers where it leads.
    func didReceiveNotificationResponse(userInfo: [AnyHashable: Any]) {
        pendingDestination = Self.destination(for: userInfo)
    }

    /// Consumes where the last tapped notification leads, if anywhere.
    func consumePendingDestination() -> NotificationDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    /// The server's paths, and the session reminder's, to where the app opens.
    nonisolated static let planGeneratorPath = "/plan/generator"
    nonisolated static let weeklyReviewPath = "/plan/review"
    nonisolated static let sourcesPath = "/settings/sources"
    nonisolated static let activityPathPrefix = "/activity/"
    nonisolated static let catchUpPath = "/plan/catch-up"

    /// Where a notification leads: by its category for the morning verdict, by its `url`
    /// otherwise. Pure, so every push the server sends is routed in a test.
    nonisolated static func destination(for userInfo: [AnyHashable: Any]) -> NotificationDestination? {
        let aps = userInfo["aps"] as? [String: Any]
        let category = userInfo["category"] as? String ?? aps?["category"] as? String
        if category == "MORNING_VERDICT" || aps?["thread-id"] as? String == "morning-verdict" {
            return .tab(.today)
        }
        guard let urlString = userInfo["url"] as? String, let url = URL(string: urlString) else { return nil }
        switch url.path {
        case planGeneratorPath: return .planGenerator
        case weeklyReviewPath: return .weeklyReview
        case sourcesPath: return .settings(.sources)
        // « Dommage pour hier » opens « Ajuster le planning » with the miss said.
        case catchUpPath:
            guard let missed = userInfo["catchUp"] as? [String: Any],
                  let label = missed["label"] as? String,
                  let day = missed["day"] as? String
            else { return .tab(.plan) }
            return .catchUp(label: label, day: day)
        // A push's `/settings` predates the Paramètres sheet.
        case "/settings": return .settings(nil)
        // « Séance dans la boîte » opens the activity that counted.
        case let path where path.hasPrefix(activityPathPrefix):
            let id = String(path.dropFirst(activityPathPrefix.count))
            return id.isEmpty || id.contains("/") ? nil : .activity(id: id)
        default: return IncomingLink.tab(forPath: url.path).map(NotificationDestination.tab)
        }
    }
}
