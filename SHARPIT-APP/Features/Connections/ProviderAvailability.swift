import Foundation

/// Which third-party sources the iPhone app offers.
///
/// Garmin's access is unofficial, and its developer program takes no new applications, so
/// Release / TestFlight / App Store builds do not offer it (App Review 5.2.2): no connect row,
/// no onboarding card, no history import, no workout push. Only DEBUG (Xcode) builds keep it.
/// Garmin watches still reach SHARPIT through Apple Health, and an account linked on the web
/// keeps syncing server-side. Turn on everywhere once access is official.
///
/// Nutrition is logged in SharpIt; there is no third-party nutrition link here (SHARPIT ADR-073).
enum ProviderAvailability {
    /// DEBUG-only. `testFlight` is ignored so a sandbox / TF flag can never resurface Garmin
    /// in external beta or App Store builds.
    static var garminInApp: Bool {
        garminInApp(debug: AppDistribution.isDebug, testFlight: AppDistribution.isTestFlight)
    }

    nonisolated static func garminInApp(debug: Bool, testFlight: Bool) -> Bool {
        _ = testFlight
        return debug
    }
}
