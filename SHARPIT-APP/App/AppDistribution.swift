import Foundation
import os
import StoreKit

/// How this copy of the app was installed: from Xcode, TestFlight or the App Store.
nonisolated enum AppDistribution {
    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// TestFlight is StoreKit `.sandbox`. Resolved once via `AppTransaction` (receipt URL is deprecated).
    private static let testFlightTask = Task<Bool, Never> {
        #if DEBUG
        return false
        #else
        do {
            switch try await AppTransaction.shared {
            case .verified(let transaction), .unverified(let transaction, _):
                return transaction.environment == .sandbox
            }
        } catch {
            return false
        }
        #endif
    }

    /// Cached answer after `prepare()`; false until StoreKit answers (App Store-safe default).
    private static let cachedTestFlight = OSAllocatedUnfairLock(initialState: false)

    /// Kick off StoreKit and wait so TestFlight-only UI (Garmin, …) is correct before first paint.
    static func prepare() async {
        let value = await testFlightTask.value
        cachedTestFlight.withLock { $0 = value }
    }

    static var isTestFlight: Bool {
        cachedTestFlight.withLock { $0 }
    }
}
