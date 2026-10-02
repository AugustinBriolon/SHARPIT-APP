import ClerkKit
import Foundation
import HealthKit

/// Wakes the app when a night is written to Apple Health — the watch ending its sleep tracking,
/// Garmin Connect syncing into Health — and sends it, so the server sends the morning verdict and
/// its proposal as soon as the night is read rather than at a fixed hour. Started at launch, a
/// background launch included: HealthKit only delivers to queries registered then.
@MainActor
enum HealthSleepObserver {
    private static var query: HKObserverQuery?
    private static let store = HKHealthStore()

    static func start() {
        guard HKHealthStore.isHealthDataAvailable(), query == nil else { return }
        let sleep = HKCategoryType(.sleepAnalysis)
        let observer = makeQuery(for: sleep)
        store.execute(observer)
        query = observer
        enableBackgroundDelivery(for: sleep, on: store)
    }

    /// Outside the main actor for the same reason as the query: HealthKit calls the completion on
    /// its own queue, and an empty closure written in `start()` still carried the main actor's
    /// isolation check — it crashed the app at launch (Sentry APPLE-IOS-2). Fails quietly until
    /// the athlete granted Health access; the next launch tries again.
    nonisolated private static func enableBackgroundDelivery(for type: HKObjectType, on store: HKHealthStore) {
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    /// The athlete's own switch decides: an account that never turned Apple Health on sends nothing.
    static func sendNight() async {
        if Clerk.shared.user == nil {
            _ = try? await Clerk.shared.refreshClient()
        }
        guard let userId = Clerk.shared.user?.id else { return }
        let source = AppleHealthSource(reader: HealthKitReader(), client: SharpitClient())
        source.bind(userId: userId)
        _ = await source.send {
            guard let token = try await Clerk.shared.auth.getToken() else { throw SharpitAPIError.unauthorized }
            return token
        }
    }

    /// Built outside the main actor: HealthKit calls the handler on its own queue, where a
    /// main-actor closure would trap. The completion is called once the night went out, so iOS
    /// keeps the app awake for the upload.
    nonisolated private static func makeQuery(for type: HKSampleType) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            let finish = ObserverCompletion(completion)
            Task {
                await HealthSleepObserver.sendNight()
                finish.run()
            }
        }
    }
}

/// HealthKit's completion handler is not `Sendable`, yet it must run once, after the upload.
nonisolated private final class ObserverCompletion: @unchecked Sendable {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
}
