import Foundation
import Testing
@testable import Sharpit

// MARK: - The String Catalog (iOS ADR 0019)

/// The catalog as committed: French keys, an English and a French value for each.
private func catalogStrings() throws -> [String: [String: Any]] {
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "SharpItShared/Localizable.xcstrings")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    return json?["strings"] as? [String: [String: Any]] ?? [:]
}

private func value(_ entry: [String: Any], _ language: String) -> String? {
    let localizations = entry["localizations"] as? [String: Any]
    let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
    return unit?["value"] as? String
}

/// A key without English shows French to an English-speaking athlete, and one without French
/// leaves no `fr.lproj` for iOS to pick: the app would open in English on a French iPhone.
@Test func everyCatalogStringHasAnEnglishAndAFrenchValue() throws {
    let strings = try catalogStrings().filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }

    #expect(strings.count > 2_000)
    let untranslated = strings.filter { value($0.value, "en") == nil || value($0.value, "fr") == nil }.map(\.key)
    #expect(untranslated.isEmpty, "Missing a language: \(untranslated.prefix(10))")
}

/// The French value is the key itself: the source code stays the French copy it always was.
@Test func theFrenchValueIsTheSourceCopy() throws {
    let drifted = try catalogStrings().filter { key, entry in value(entry, "fr").map { $0 != key } ?? false }
    #expect(drifted.isEmpty, "French drifted from its key: \(drifted.keys.prefix(10))")
}

// MARK: - Language choice

@Test func theAppSpeaksFrenchUnderTheFrenchTestLanguage() {
    #expect(AppLanguage.current == .french)
    #expect(String(localized: "Langue de l'appareil") == "Langue de l'appareil")
}

@Test func eachLanguageIsListedUnderItsOwnName() {
    #expect(AppLanguage.french.displayName == "Français")
    #expect(AppLanguage.english.displayName == "English")
    #expect(AppLanguage.allCases == [.system, .french, .english])
}
