import SwiftUI

/// When a food was eaten (SHARPIT ADR-137): minutes after the training day's local midnight, the
/// server's `eatenMinute`. « Fil de la journée » places the meal there, and the coach's reading of
/// the day reads it around the sessions.
///
/// Only a time the athlete stands behind is sent: one they set, or « now » when they log the meal
/// of the hour on the spot. A food logged in the evening for the morning opens on the meal's usual
/// hour and goes out without a time unless they set it — the server keeps no guess as a fact.
nonisolated struct FoodEatenTime: Equatable, Sendable {
    /// The minute shown in the picker.
    var minute: Int
    /// The athlete set it by hand.
    var isSet: Bool
    /// It opened on the clock: the meal of the hour, logged today.
    var isNow: Bool

    /// What goes to the server: the minute, or nil when it is only the meal's usual hour.
    var sent: Int? { isSet || isNow ? minute : nil }

    /// The hour the server stands a meal at when none of its foods has one (`day-timeline.ts`).
    static func usualMinute(of meal: FoodLogMeal) -> Int {
        switch meal {
        case .breakfast: 8 * 60
        case .lunch: 12 * 60 + 30
        case .snacks: 16 * 60
        case .dinner: 19 * 60 + 30
        }
    }

    /// A new food: now, when the day is today and the meal the one of the hour; else its usual hour.
    static func initial(
        meal: FoodLogMeal,
        trainingDayId: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FoodEatenTime {
        let isToday = trainingDayId == TrainingDayId.today(in: calendar, now: now)
        guard isToday, FoodLogMeal.suggested(at: now, calendar: calendar) == meal else {
            return FoodEatenTime(minute: usualMinute(of: meal), isSet: false, isNow: false)
        }
        return FoodEatenTime(minute: minuteOfDay(now, calendar: calendar), isSet: false, isNow: true)
    }

    /// A logged food: its time when it has one, else its meal's usual hour, not to be sent.
    static func existing(_ entry: V1FoodLogEntry) -> FoodEatenTime {
        if let minute = entry.eatenMinute {
            return FoodEatenTime(minute: minute, isSet: true, isNow: false)
        }
        return FoodEatenTime(minute: usualMinute(of: entry.meal), isSet: false, isNow: false)
    }

    /// Another meal picked: an untouched time follows it; one the athlete set stays.
    mutating func follow(
        meal: FoodLogMeal,
        trainingDayId: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard !isSet else { return }
        self = Self.initial(meal: meal, trainingDayId: trainingDayId, now: now, calendar: calendar)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// « 07:45 », as the rail and the server write it.
    static func clock(_ minute: Int) -> String {
        let wrapped = ((minute % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }
}

/// « Heure » beside the meal: the system's compact time picker. Setting it marks the time as the
/// athlete's own, so it is sent even where it opened on the meal's usual hour.
struct FoodEatenTimePicker: View {
    @Binding var time: FoodEatenTime

    /// The picker works on dates: today's date at the minute, read back as a minute.
    private var date: Binding<Date> {
        Binding(
            get: {
                let start = Calendar.current.startOfDay(for: .now)
                return Calendar.current.date(byAdding: .minute, value: time.minute, to: start) ?? start
            },
            set: { newValue in
                let minute = FoodEatenTime.minuteOfDay(newValue)
                guard minute != time.minute else { return }
                time.minute = minute
                time.isSet = true
            }
        )
    }

    var body: some View {
        DatePicker("Heure", selection: date, displayedComponents: .hourAndMinute)
            .datePickerStyle(.compact)
            .tint(SharpitColor.primary)
    }
}
