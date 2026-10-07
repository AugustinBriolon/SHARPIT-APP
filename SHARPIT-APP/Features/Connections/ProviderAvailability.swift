import Foundation

/// Which third-party sources the iPhone app offers.
///
/// Garmin's access is unofficial, and its developer program takes no new applications, so the
/// App Store build does not offer it (App Review 5.2.2): no connect row, no onboarding card, no
/// history import, no workout push. Garmin watches still reach SHARPIT through Apple Health, and
/// an account linked on the web keeps syncing server-side. Builds from Xcode and TestFlight keep
/// all of it, for the athlete's own phone and the beta. Turn on everywhere once access is official.
///
/// Nutrition is logged in SharpIt; there is no third-party nutrition link here (SHARPIT ADR-073).
enum ProviderAvailability {
    /// Recomputed when read so a TestFlight flag resolved after launch is picked up.
    static var garminInApp: Bool {
        garminInApp(debug: AppDistribution.isDebug, testFlight: AppDistribution.isTestFlight)
    }

    nonisolated static func garminInApp(debug: Bool, testFlight: Bool) -> Bool {
        debug || testFlight
    }
}
