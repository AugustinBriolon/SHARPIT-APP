import UIKit
import UserNotifications

/// Application delegate handling APNs registration callbacks and foreground notification presentation.
@MainActor
final class SharpitAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Before anything else returns: a background launch by HealthKit delivers only to
        // observers registered here.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            HealthUploadObserver.start()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.didRegisterForRemoteNotifications(with: deviceToken)
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

    // Foreground: banner + sound. No badge — the athlete is already in the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Action when user taps on the push notification banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        // Store before completionHandler — a cold launch can otherwise finish before RootView reads it.
        PushNotificationManager.shared.didReceiveNotificationResponse(userInfo: userInfo)
        completionHandler()
    }
}
