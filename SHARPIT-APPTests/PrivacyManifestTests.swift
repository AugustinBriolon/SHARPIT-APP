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

/// UserDefaults (app-only storage) and the activity disk cache's file dates (`ActivityDiskCache`).
@Test func theAppDeclaresItsRequiredReasonAPIs() throws {
    let entries = try #require(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    let reasons = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, [String])? in
        guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
              let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
        return (type, reasons)
    })
    #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])
    #expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["C617.1"])
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
