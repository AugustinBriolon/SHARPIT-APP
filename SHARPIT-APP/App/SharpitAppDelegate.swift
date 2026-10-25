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
        // observers registered here. UIKit calls this on main; assumeIsolated avoids an
        // async hop that would register too late for a HK wake (APPLE-IOS-2).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            MainActor.assumeIsolated {
                HealthUploadObserver.start()
                CrashReporting.note("health.observer.started", category: "health")
            }
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
    // On the main actor: UIKit's fetch completion handler must be called on the main thread,
    // otherwise UIKit asserts "Call must be made on main thread" while snapshotting (APPLE-IOS-7).
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard userInfo["refresh"] as? String == "today" else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let success = await WidgetSnapshotPublisher.refreshInBackground()
            completionHandler(success ? .newData : .failed)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[APNs] Registration failed: \(error.localizedDescription)")
        #endif
    }

    // UserNotifications calls these on its own queue, not main: a main-actor delegate method
    // traps there (`_dispatch_assert_queue_fail`), as a local reminder firing at launch did.

    // Foreground: banner + sound. No badge — the athlete is already in the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Action when user taps on the push notification banner. The destination is stored before
    // returning — otherwise a cold launch could finish the callback before RootView sees a tap.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let destination = PushNotificationManager.destination(for: response.notification.request.content.userInfo)
        await PushNotificationManager.shared.didReceiveNotificationResponse(destination: destination)
    }
}
