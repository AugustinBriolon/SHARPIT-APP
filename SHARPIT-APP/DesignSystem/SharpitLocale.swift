import Foundation

/// The app speaks French, whatever the device does.
///
/// `Date.formatted(.dateTime…)` resolves against `Locale.autoupdatingCurrent`, not the
/// SwiftUI environment, so setting `\.locale` on the root is not enough — a French screen
/// rendered "MON" and "M T W T F S S" on an English device. Every date the athlete reads
/// goes through here instead.
enum SharpitLocale {
    static let french = Locale(identifier: "fr_FR")
}

extension Date {
    /// Formats in French, matching the web's copy.
    func sharpitFormatted(_ style: Date.FormatStyle) -> String {
        style.locale(SharpitLocale.french).format(self)
    }
}
