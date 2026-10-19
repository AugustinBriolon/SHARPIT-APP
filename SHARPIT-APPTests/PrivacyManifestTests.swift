import Foundation
import Testing
@testable import Sharpit

/// App Store Connect refuses a build whose required-reason APIs are not declared.
private func manifest() throws -> [String: Any] {
    let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    let data = try Data(contentsOf: url)
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

@Test func theAppDeclaresNoTracking() throws {
    let plist = try manifest()
    #expect(plist["NSPrivacyTracking"] as? Bool == false)
    #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
}

private func requiredReasons(_ plist: [String: Any]) throws -> [String: [String]] {
    let entries = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    return Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, [String])? in
        guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
              let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
        return (type, reasons)
    })
}

/// UserDefaults (the app's own and the widgets' app group) and the activity disk cache's file
/// dates (`ActivityDiskCache`).
@Test func theAppDeclaresItsRequiredReasonAPIs() throws {
    let reasons = try requiredReasons(manifest())
    #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1", "1C8F.1"])
    #expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["C617.1"])
}

/// The widget extension is its own bundle: it reads the snapshot through the app group's defaults.
@Test func theWidgetExtensionDeclaresItsRequiredReasonAPIs() throws {
    let plugins = try #require(Bundle.main.builtInPlugInsURL)
    let appex = try #require(try FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
        .first { $0.pathExtension == "appex" })
    let data = try Data(contentsOf: appex.appending(path: "PrivacyInfo.xcprivacy"))
    let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(plist["NSPrivacyTracking"] as? Bool == false)
    #expect(try requiredReasons(plist)["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1", "1C8F.1"])
}

@Test func theAppDeclaresHealthAndFitnessAsCollectedForItsOwnUse() throws {
    let entries = try #require(try manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
    let types = Set(entries.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
    #expect(types.isSuperset(of: [
        "NSPrivacyCollectedDataTypeHealth",
        "NSPrivacyCollectedDataTypeFitness",
        "NSPrivacyCollectedDataTypeUserID",
        "NSPrivacyCollectedDataTypeCrashData",
    ]))
    #expect(entries.allSatisfy { $0["NSPrivacyCollectedDataTypeTracking"] as? Bool == false })
}
