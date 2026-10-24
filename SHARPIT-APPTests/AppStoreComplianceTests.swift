import Foundation
import Testing
import UIKit
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
        .appending(path: "SHARPIT-APP/SharpIt.entitlements")
    let plist = try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: entitlements), format: nil) as? [String: Any]
    )
    #expect(plist["com.apple.developer.healthkit"] as? Bool == true)
    #expect(plist["com.apple.developer.healthkit.access"] == nil)
}

/// MyFitnessPal was withdrawn (SHARPIT ADR-073): nothing in the app target may call link, sync or import routes.
@Test func theAppNeverLinksMyFitnessPal() throws {
    let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SHARPIT-APP")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    for case let file as URL in files where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("/api/v1/myfitnesspal"), "\(file.lastPathComponent) calls a MyFitnessPal link route")
        #expect(!text.contains("import/myfitnesspal"), "\(file.lastPathComponent) calls a MyFitnessPal import route")
        #expect(!text.contains("myfitnesspal.com"), "\(file.lastPathComponent) opens MyFitnessPal's site")
    }
}

/// Garmin is linked only through its official Personal API key (web ADR-103, `docs/adr/0023`): the
/// app target calls the key and disconnect routes, never the retired SSO handoff, the token importer
/// nor a workout push, which Garmin reserves to its business tiers.
@Test func theAppLinksGarminOnlyThroughItsOfficialKey() throws {
    let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SHARPIT-APP")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    for case let file as URL in files where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("garmin/handoff"), "\(file.lastPathComponent) opens the retired Garmin SSO")
        #expect(!text.contains("import-garmin"), "\(file.lastPathComponent) imports from Garmin")
        #expect(!text.contains("connect/garmin"), "\(file.lastPathComponent) handles a Garmin SSO callback")
        #expect(!text.contains("garmin/workouts"), "\(file.lastPathComponent) pushes a workout to Garmin")
    }
}

/// The official source shows its own mark, as the other sources do.
@Test func garminShowsItsOwnMark() {
    #expect(ProviderLogo.Provider(integrationId: "garmin") == .garmin)
    #expect(UIImage(named: "Provider/Garmin") != nil)
}

/// The barcode scanner opens the camera: App Review refuses a build that asks without saying why.
@Test func theAppExplainsWhyItUsesTheCamera() {
    let text = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
    #expect(text?.contains("code-barres") == true)
}
