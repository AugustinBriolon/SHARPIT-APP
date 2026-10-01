import Foundation
import Testing
@testable import Sharpit

/// Only HTTPS through Apple's own stack: exempt, so App Store Connect stops asking at upload.
@Test func theAppDeclaresNoNonExemptEncryption() {
    #expect(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool == false)
}

/// WeatherKit requires its legal page wherever its data shows, even before it answered.
@Test func weatherAttributionAlwaysHasALegalPage() {
    #expect(AppleWeatherAttribution.fallbackLegalPageURL.host() == "weatherkit.apple.com")
}

/// App Store Connect refuses a HealthKit build without both purpose strings, even read-only.
@Test func theAppExplainsEveryHealthKitPurpose() {
    for key in ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"] {
        let text = Bundle.main.object(forInfoDictionaryKey: key) as? String
        #expect(text?.isEmpty == false, "\(key) missing")
    }
}

/// Clinical records are never read: the entitlement would only draw review questions.
@Test func theAppDoesNotAskForHealthRecords() throws {
    let entitlements = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SHARPIT-APP/SHARPIT.entitlements")
    let plist = try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: entitlements), format: nil) as? [String: Any]
    )
    #expect(plist["com.apple.developer.healthkit"] as? Bool == true)
    #expect(plist["com.apple.developer.healthkit.access"] == nil)
}

/// Garmin's access is unofficial: the App Store build offers no way to connect it (5.2.2).
@Test func theAppStoreBuildDoesNotOfferGarmin() {
    #expect(ProviderAvailability.garminInApp == false)
}

/// The barcode scanner opens the camera: App Review refuses a build that asks without saying why.
@Test func theAppExplainsWhyItUsesTheCamera() {
    let text = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
    #expect(text?.contains("code-barres") == true)
}
