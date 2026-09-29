import CoreGraphics
import Foundation

/// How the widgets read a section — pure, shared so the rules are tested with the app.
extension WidgetSnapshot.Nutrition {
    /// Eaten against the day's budget, 0…100 for the dial.
    var dialScore: CGFloat? {
        guard let calories, let calorieGoal, calorieGoal > 0 else { return nil }
        return CGFloat(min(calories / calorieGoal, 1) * 100)
    }

    /// The figure inside the dial: what is left, or how far past.
    var dialFigure: String {
        guard let remaining else { return SharpitFigureFormat.kcal(calories) }
        return SharpitFigureFormat.kcal(abs(remaining))
    }

    var dialCaption: String {
        guard let remaining else { return "kcal aujourd'hui" }
        return remaining >= 0 ? "kcal restantes" : "kcal au-delà"
    }

    var hasLog: Bool { (calories ?? 0) > 0 }
}

extension WidgetSnapshot.Weight {
    var change: Double? { previousKilograms.map { kilograms - $0 } }

    /// Whether the change went towards the target; nil without one.
    var movesTowardsTarget: Bool? {
        guard let targetKilograms, let change, abs(change) >= 0.05 else { return nil }
        return (targetKilograms - kilograms).magnitude < (targetKilograms - (kilograms - change)).magnitude
    }

    var changeLine: String? {
        guard let change else { return nil }
        let window = changeWindowDays.map { " · \($0) j" } ?? ""
        return SharpitFigureFormat.kilogramChange(change) + window
    }

    var targetLine: String? {
        guard let targetKilograms else { return nil }
        let left = targetKilograms - kilograms
        if abs(left) < 0.05 { return "Objectif \(SharpitFigureFormat.target(targetKilograms)) atteint" }
        return "Encore \(SharpitFigureFormat.kilograms(abs(left))) kg · objectif \(SharpitFigureFormat.target(targetKilograms))"
    }
}


// MARK: - Volume

/// The sport a volume widget is set to; nil counts every sport.
nonisolated struct WeekVolume: Equatable, Sendable {
    nonisolated struct Day: Equatable, Sendable, Identifiable {
        var dayId: String
        /// « L », « M »…
        var initial: String
        /// Kilometres, or minutes when the volume is read in time.
        var value: Double
        var isToday: Bool
        var isFuture: Bool

        var id: String { dayId }
    }

    var days: [Day]
    var sessionCount: Int
    var distanceKilometers: Double
    var minutes: Double
    /// Last week up to the same weekday, in the same unit as the figure.
    var lastWeekSoFar: Double
    /// Read in kilometres for a sport whose sessions carry them; in time otherwise — strength,
    /// all sports (kilometres of swimming and of cycling add up to nothing), or a sport recorded
    /// without distances.
    var readsInDistance: Bool

    var figure: Double { readsInDistance ? distanceKilometers : minutes }

    var peakDay: Double { days.map(\.value).max() ?? 0 }
}

extension WidgetSnapshot.Training {
    /// The week holding `date`, Monday first, for `sport` (nil: all of them).
    func week(of date: Date, sport: V1ActivityType?, calendar base: Calendar = .current) -> WeekVolume {
        var calendar = base
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: date)
        let monday = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let counted = self.sessions.filter { sport == nil || $0.sport == sport }
        // Kilometres only where the sessions carry them: a ride recorded without a distance
        // read « 0,0 km » beside its hour and a quarter.
        let readsInDistance = sport != nil && sport != .strength
            && counted.contains { ($0.distanceMeters ?? 0) > 0 }
        func value(_ session: WidgetSnapshot.TrainedSession) -> Double {
            readsInDistance ? (session.distanceMeters ?? 0) / 1000 : (session.durationSeconds ?? 0) / 60
        }
        func recorded(on day: Date) -> [WidgetSnapshot.TrainedSession] {
            let id = WidgetSnapshot.dayId(day, calendar: calendar)
            return counted.filter { $0.dayId == id }
        }
        let initials = ["L", "M", "M", "J", "V", "S", "D"]
        let weekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        let days = weekDates.enumerated().map { index, day in
            WeekVolume.Day(
                dayId: WidgetSnapshot.dayId(day, calendar: calendar),
                initial: initials[index],
                value: recorded(on: day).map(value).reduce(0, +),
                isToday: day == today,
                isFuture: day > today
            )
        }
        let thisWeek = weekDates.filter { $0 <= today }.flatMap(recorded(on:))
        let elapsed = weekDates.filter { $0 <= today }.count
        let lastWeek = weekDates.prefix(elapsed)
            .compactMap { calendar.date(byAdding: .day, value: -7, to: $0) }
            .flatMap(recorded(on:))
        return WeekVolume(
            days: days,
            sessionCount: thisWeek.count,
            distanceKilometers: thisWeek.compactMap(\.distanceMeters).reduce(0, +) / 1000,
            minutes: thisWeek.compactMap(\.durationSeconds).reduce(0, +) / 60,
            lastWeekSoFar: lastWeek.map(value).reduce(0, +),
            readsInDistance: readsInDistance
        )
    }
}

extension WeekVolume {
    /// « 32,4 » km or « 3 h 10 ».
    var figureText: String {
        readsInDistance ? SharpitFigureFormat.kilometers(distanceKilometers) : SharpitFigureFormat.duration(minutes: minutes)
    }

    var unit: String { readsInDistance ? "km" : "" }

    /// « 4 séances · 3 h 10 » — the other half of the week, under the figure.
    var detailLine: String {
        let count = sessionCount == 1 ? "1 séance" : "\(sessionCount) séances"
        guard readsInDistance, minutes > 0 else { return count }
        return "\(count) · \(SharpitFigureFormat.duration(minutes: minutes))"
    }

    /// « Sem. dernière à ce jour : 28,1 km » — a fact, not a verdict.
    var lastWeekLine: String {
        let figure = readsInDistance
            ? "\(SharpitFigureFormat.kilometers(lastWeekSoFar)) km"
            : SharpitFigureFormat.duration(minutes: lastWeekSoFar)
        return "Sem. dernière à ce jour : \(figure)"
    }
}

// MARK: - Goal

extension WidgetSnapshot.Goal {
    func daysLeft(from date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: self.date)).day ?? 0
    }

    /// « 42 jours », « Demain », « Aujourd'hui ».
    func countdownCaption(from date: Date, calendar: Calendar = .current) -> String {
        switch daysLeft(from: date, calendar: calendar) {
        case 0: "Aujourd'hui"
        case 1: "Demain"
        case let days: days >= 21 ? "\(days) jours · \(days / 7) sem." : "\(days) jours"
        }
    }

    /// « dim. 14 juin 2027 ».
    var dateLine: String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).year().locale(Locale(identifier: "fr_FR")))
    }

    /// Format, place and target, what is known of them.
    var contextLine: String? {
        let parts = [format, location, targetPerformance.map { "visé \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
