import Foundation

/// The language SharpIt speaks: the device's, or one the athlete picked in Paramètres (iOS ADR 0019).
///
/// The pick is the bundle's own `AppleLanguages`, the key iOS's per-app Language setting writes,
/// so the two never disagree. A bundle resolves its localization once per process, so a pick
/// applies at the next launch. The widget extension is its own process: the app publishes the
/// language it resolved to the App Group, and the extension adopts it.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case french = "fr"
    case english = "en"

    var id: String { rawValue }

    private static let appleLanguagesKey = "AppleLanguages"
    private static let groupKey = "appLanguage"

    private static var group: UserDefaults {
        UserDefaults(suiteName: "group.app.sharpit.ios") ?? .standard
    }

    /// What the athlete picked: `.system` while the app follows the device.
    static var chosen: AppLanguage {
        guard let domain = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: domain)?[appleLanguagesKey] as? [String],
              let first = languages.first else { return .system }
        return AppLanguage(code: first) ?? .system
    }

    /// Records a pick; it applies at the next launch of the app and its widgets.
    static func choose(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: appleLanguagesKey)
        }
    }

    /// The language this process shows: `fr` or `en`. A device in neither gets English.
    static let current: AppLanguage = AppLanguage(code: Bundle.main.preferredLocalizations.first ?? "en") ?? .english

    /// Formats in the language shown, with the device's region (decimal comma, week start…).
    static let locale = Locale(languageCode: .init(current.rawValue), languageRegion: Locale.current.region)

    /// App side: tells the widget extension which language the app resolved.
    static func publishToExtensions() {
        group.set(current.rawValue, forKey: groupKey)
    }

    /// Extension side: follows the app's language from the extension's next launch.
    static func adoptAppLanguage() {
        guard let code = group.string(forKey: groupKey), code != current.rawValue,
              let language = AppLanguage(code: code) else { return }
        choose(language)
    }

    private init?(code: String) {
        if code.hasPrefix("fr") { self = .french } else if code.hasPrefix("en") { self = .english } else { return nil }
    }
}
