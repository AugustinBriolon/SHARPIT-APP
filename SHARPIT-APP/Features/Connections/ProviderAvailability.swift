import Foundation

/// Which third-party sources the iPhone app offers.
///
/// Garmin's access is unofficial, and its developer program takes no new applications, so the
/// App Store build does not offer it (App Review 5.2.2): no connect row, no onboarding card, no
/// history import, no workout push. Garmin watches still reach SHARPIT through Apple Health, and
/// an account linked on the web keeps syncing server-side. Turn back on once access is official.
///
/// MyFitnessPal's access is unofficial too, and it has no switch here: the app has no way to
/// link it at all (docs/adr/0010). The athlete imports their own MyFitnessPal export from
/// Nutrition instead; days imported or synced on the web still show, read-only.
enum ProviderAvailability {
    static let garminInApp = false
}
