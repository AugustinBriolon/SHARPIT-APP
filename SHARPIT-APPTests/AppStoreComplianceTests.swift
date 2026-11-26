import Foundation
import Testing
import UIKit
@testable import Sharpit

/// Only HTTPS through Apple's own stack: exempt, so App Store Connect stops asking at upload.
@Test func theAppDeclaresNoNonExemptEncryption() {
    #expect(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool == false)
}

/// Weather is the server's (Open-Meteo, per session and activity: `docs/adr/0041`): no WeatherKit, whose
/// attribution got 1.0 rejected, and no location prompt, which only that chip needed.
@Test func theAppAsksForNeitherWeatherKitNorLocation() throws {
    let entitlements = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SHARPIT-APP/SharpIt.entitlements")
    let plist = try #require(
        try PropertyListSerialization.propertyList(from: Data(contentsOf: entitlements), format: nil) as? [String: Any]
    )
    #expect(plist["com.apple.developer.weatherkit"] == nil)
    #expect(Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") == nil)
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

/// Garmin is linked only through the Connect Developer Program OAuth (web ADR-105,
/// `docs/adr/0024`): the in-app handoff, like Strava and Withings — never the retired SSO,
/// the token importer, nor a personal API key.
@Test func theAppLinksGarminOnlyThroughItsOAuthHandoff() throws {
    #expect(DisconnectableSource.garmin.connectsViaOAuthHandoff)
    let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "SHARPIT-APP")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    for case let file as URL in files where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(!text.contains("import-garmin"), "\(file.lastPathComponent) imports from Garmin")
        #expect(!text.contains("garmin/connect\""), "\(file.lastPathComponent) posts a Garmin key")
        #expect(!text.contains("personalApiToken"), "\(file.lastPathComponent) asks for a personal key")
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
