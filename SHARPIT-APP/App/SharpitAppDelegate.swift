import UIKit
import UserNotifications

/// Application delegate handling APNs registration callbacks and foreground notification presentation.
final class SharpitAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Before anything else returns: a background launch by HealthKit delivers only to
        // observers registered here.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            HealthSleepObserver.start()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didRegisterForRemoteNotifications(with: deviceToken)
        }
    }

    /// A silent push after the server synced the athlete's sources: today is read again so the
    /// widgets show what just came in, app open or not.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard userInfo["refresh"] as? String == "today" else { return .noData }
        return await WidgetSnapshotPublisher.refreshInBackground() ? .newData : .failed
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[APNs] Registration failed: \(error.localizedDescription)")
        #endif
    }

    // Foreground presentation: display banner, sound and badge for morning verdict.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    // Action when user taps on the push notification banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            PushNotificationManager.shared.didReceiveNotificationResponse(userInfo: userInfo)
        }
        completionHandler()
    }
}
