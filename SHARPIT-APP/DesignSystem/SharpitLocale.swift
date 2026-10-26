import Foundation

/// The locale every date and number the athlete reads is formatted in: the app's language
/// (`AppLanguage`), with the device's region.
///
/// `Date.formatted(.dateTime…)` resolves against `Locale.autoupdatingCurrent`, not the
/// SwiftUI environment, so setting `\.locale` on the root is not enough — a French screen
/// rendered "MON" and "M T W T F S S" on an English device. Every date goes through here instead.
enum SharpitLocale {
    static let current = AppLanguage.locale
}

extension Date {
    /// Formats in the app's language, whatever the device's.
    func sharpitFormatted(_ style: Date.FormatStyle) -> String {
        style.locale(SharpitLocale.current).format(self)
    }
}

extension String {
    /// « lundi 26 octobre » opening a line takes a capital; French formats it lower case.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
