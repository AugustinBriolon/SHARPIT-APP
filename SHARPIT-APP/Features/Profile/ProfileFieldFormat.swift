import Foundation

/// Reading and writing the values a profile field holds.
///
/// A threshold is stored as a number of seconds but entered as `4:15`, and a bedtime as
/// minutes after midnight but entered as `22:30`. These convert both ways, and mirror the
/// web's `profile-input-format.ts` so the same typing works on both platforms.
///
/// Separate from `ActivityFormat.pace`, which is display-only: it appends `/km` and rounds
/// for a readout, where a field has to round-trip exactly what the athlete typed.
nonisolated enum ProfileFieldFormat {
    /// `255` → `"4:15"`. Empty for a threshold that was never set.
    static func pace(_ secondsPerUnit: Double?) -> String {
        guard let secondsPerUnit, secondsPerUnit > 0 else { return "" }
        let total = Int(secondsPerUnit.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// `"4:15"` → `255`. Nil for anything that is not `m:ss`, so a half-typed value never
    /// saves as a wrong number.
    static func parsePace(_ text: String) -> Double? {
        guard let (major, minor) = parts(of: text) else { return nil }
        guard minor < 60 else { return nil }
        let seconds = major * 60 + minor
        return seconds > 0 ? Double(seconds) : nil
    }

    /// `1350` → `"22:30"`, minutes after local midnight.
    static func clock(_ minutesAfterMidnight: Int?) -> String {
        guard let minutesAfterMidnight, minutesAfterMidnight >= 0 else { return "" }
        let minutes = minutesAfterMidnight % (24 * 60)
        return "\(String(format: "%02d", minutes / 60)):\(String(format: "%02d", minutes % 60))"
    }

    /// `"22:30"` → `1350`. A bedtime past midnight is a valid time of day, not a duration,
    /// so hours are bounded at 23.
    static func parseClock(_ text: String) -> Int? {
        guard let (hours, minutes) = parts(of: text) else { return nil }
        guard hours < 24, minutes < 60 else { return nil }
        return hours * 60 + minutes
    }

    /// `510` → `"8 h 30"` — a sleep target reads as a duration, never as a clock time.
    static func duration(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }

    /// `510` → `"8,5"`. The server stores a sleep target in minutes; the web types it in
    /// hours, in quarter steps, and so does the app.
    static func hours(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "" }
        return decimal(Double(minutes) / 60)
    }

    /// `"8,5"` → `510`, rounded to the minute as the web rounds it.
    static func parseHours(_ text: String) -> Int? {
        guard let hours = parseDecimal(text) else { return nil }
        let minutes = Int((hours * 60).rounded())
        return minutes > 0 ? minutes : nil
    }

    /// `1990-04-12`, the day the server's `@db.Date` reads.
    ///
    /// UTC, because that is the calendar the column stores: a local midnight in Paris is the
    /// previous day there. No time and no zone marker either — the web parses a birth date
    /// with `^(\d{4})-(\d{2})-(\d{2})$` and rejects anything longer.
    static func isoDay(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    /// Two birth dates are the same when they name the same UTC day. Comparing instants
    /// would resend an unchanged date on every save, because the server answers midnight UTC
    /// and a picker holds whatever moment it was given.
    static func isSameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        isoDay(lhs) == isoDay(rhs)
    }

    static func integer(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    static func parseInteger(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    /// One decimal, as a weight is weighed. The comma is the French decimal separator and
    /// is what the number pad offers, so it is read as well as written.
    static func decimal(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func parseDecimal(_ text: String) -> Double? {
        let normalised = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalised.isEmpty, let value = Double(normalised), value > 0 else { return nil }
        return value
    }

    /// The two halves of a `m:ss` or `h:mm` entry, both required.
    private static func parts(of text: String) -> (Int, Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let halves = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard halves.count == 2,
              let major = Int(halves[0]), major >= 0,
              let minor = Int(halves[1]), minor >= 0 else { return nil }
        return (major, minor)
    }
}
