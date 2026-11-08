import Foundation

/// The date shapes the API sends and reads, in one place: an instant (ISO 8601, with or without
/// fractional seconds) and a day (`yyyy-MM-dd`). Each reader keeps the time zone it always had;
/// only the parsing and formatting live here, so a format change lands once.
nonisolated enum APIDate {
    /// Gregorian in the athlete's time zone: the day as their calendar shows it.
    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Gregorian in UTC: a day the server keeps as UTC midnight.
    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// An instant, with or without fractional seconds.
    static func instant(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// An instant as the API writes it: with milliseconds, in UTC.
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// A `yyyy-MM-dd` day, read at its midnight in `calendar`'s time zone; nil when it does not parse.
    static func day(_ text: String, calendar: Calendar = localCalendar) -> Date? {
        formatter(calendar).date(from: text)
    }

    /// A day as `yyyy-MM-dd` in `calendar`'s time zone.
    static func dayString(_ date: Date, calendar: Calendar = localCalendar) -> String {
        formatter(calendar).string(from: date)
    }

    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
