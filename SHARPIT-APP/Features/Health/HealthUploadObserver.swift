import ClerkKit
import Foundation
import HealthKit

/// Wakes the app when Apple Health receives what the server answers to, and sends it:
/// - a night — the watch ending its sleep tracking, Garmin Connect syncing into Health — so the
///   morning verdict and its proposal go out as soon as the night is read, not at a fixed hour;
/// - a workout, so the server pairs it with the plan and says « Séance dans la boîte » within the
///   hour rather than once the athlete opens the app.
///
/// Started at launch, a background launch included: HealthKit only delivers to queries
/// registered then.
@MainActor
enum HealthUploadObserver {
    private static var queries: [HKObserverQuery] = []
    private static let store = HKHealthStore()
    /// One send at a time: a night and a workout often land together, and two sends would read
    /// and upload the same samples twice.
    private static var inFlight: Task<Void, Never>?

    private static var observedTypes: [HKSampleType] {
        [HKCategoryType(.sleepAnalysis), HKWorkoutType.workoutType()]
    }

    static func start() {
        guard HKHealthStore.isHealthDataAvailable(), queries.isEmpty else { return }
        for type in observedTypes {
            let observer = makeQuery(for: type)
            store.execute(observer)
            queries.append(observer)
            enableBackgroundDelivery(for: type, on: store)
        }
    }

    /// Outside the main actor for the same reason as the query: HealthKit calls the completion on
    /// its own queue, and an empty closure written in `start()` still carried the main actor's
    /// isolation check — it crashed the app at launch (Sentry APPLE-IOS-2). Fails quietly until
    /// the athlete granted Health access; the next launch tries again.
    nonisolated private static func enableBackgroundDelivery(for type: HKObjectType, on store: HKHealthStore) {
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    /// Queued behind a send already under way, so what arrived meanwhile still goes out.
    static func sendNewSamples() async {
        let previous = inFlight
        let next = Task {
            await previous?.value
            await send()
        }
        inFlight = next
        await next.value
    }

    /// The athlete's own switch decides: an account that never turned Apple Health on sends nothing.
    private static func send() async {
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
    /// main-actor closure would trap. The completion is called once the samples went out, so iOS
    /// keeps the app awake for the upload.
    nonisolated private static func makeQuery(for type: HKSampleType) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            let finish = ObserverCompletion(completion)
            Task {
                await HealthUploadObserver.sendNewSamples()
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
