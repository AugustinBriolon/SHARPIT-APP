import EventKit
import Foundation

/// One planned session as an event of the iPhone's calendar.
nonisolated struct PlanCalendarEvent: Equatable, Sendable {
    /// `sharpit://plan/session/<id>`: the event's key, and the link back to the session.
    let url: URL
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let notes: String?
}

/// What the calendar should hold — pure, so the rules are tested. A session with a time takes
/// its slot (its duration, an hour without one); a session without one is an all-day event.
/// Sessions done or linked to an activity stay: the calendar is a diary of the plan too.
nonisolated enum PlanCalendarPlanner {
    /// How far ahead the plan is copied.
    static let horizonDays = 21
    static let defaultMinutes = 60

    static func url(for sessionId: String) -> URL {
        URL(string: "sharpit://plan/session/\(sessionId)")!
    }

    static func events(for sessions: [V1PlannedSessionItem], calendar: Calendar = .current) -> [PlanCalendarEvent] {
        sessions.compactMap { event(for: $0, calendar: calendar) }
    }

    private static func event(for session: V1PlannedSessionItem, calendar: Calendar) -> PlanCalendarEvent? {
        let day = calendar.startOfDay(for: session.date)
        let name = session.title ?? session.displayType
        let title = session.isKey ? "\(name) · clé" : name
        let notes = [session.durationMin.map { "\($0) min" }, session.notes].compactMap { $0 }.joined(separator: "\n")
        let minutes = session.durationMin ?? defaultMinutes
        if let clock = session.startTime.flatMap(Self.clock),
           let start = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day) {
            return PlanCalendarEvent(
                url: url(for: session.id), title: title, start: start,
                end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: false,
                notes: notes.isEmpty ? nil : notes
            )
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        return PlanCalendarEvent(
            url: url(for: session.id), title: title, start: day, end: next, isAllDay: true,
            notes: notes.isEmpty ? nil : notes
        )
    }

    private static func clock(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}

/// Copies the plan into a « SharpIt » calendar on the iPhone (SharpIt Pro). Each refresh makes
/// the calendar equal to the plan over the next three weeks: a session moved moves its event, a
/// session removed removes it. Only events SharpIt wrote are ever touched — they live in their
/// own calendar, keyed by their link.
@MainActor
final class PlanCalendarSync {
    static let shared = PlanCalendarSync()

    static let enabledKey = "planCalendarSync.enabled"
    private static let calendarIdKey = "planCalendarSync.calendarId"
    static let calendarTitle = "SharpIt"

    private let store = EKEventStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    /// Asks iOS for the calendar, then turns the copy on. False when the athlete refused.
    func enable() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        defaults.set(granted, forKey: Self.enabledKey)
        return granted
    }

    /// Turns the copy off and removes the SharpIt calendar with every event it held.
    func disable() {
        defaults.set(false, forKey: Self.enabledKey)
        if let calendar = existingCalendar() {
            try? store.removeCalendar(calendar, commit: true)
        }
        defaults.removeObject(forKey: Self.calendarIdKey)
    }

    func refresh(
        isPro: Bool,
        plan: any PlannedSessionServing,
        tokenProvider: () async throws -> String,
        now: Date = .now
    ) async {
        guard isEnabled, isPro, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: PlanCalendarPlanner.horizonDays, to: start) ?? now
        do {
            let sessions = try await plan.plannedSessions(from: start, to: end, token: try await tokenProvider())
            guard let calendar = sharpitCalendar() else { return }
            apply(PlanCalendarPlanner.events(for: sessions), to: calendar, from: start, to: end)
        } catch {
            // Offline or signed out: the calendar keeps what it holds.
        }
    }

    private func apply(_ wanted: [PlanCalendarEvent], to calendar: EKCalendar, from start: Date, to end: Date) {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        var existing = Dictionary(
            store.events(matching: predicate).compactMap { event in event.url.map { ($0, event) } },
            uniquingKeysWith: { first, _ in first }
        )
        for event in wanted {
            let target = existing.removeValue(forKey: event.url) ?? EKEvent(eventStore: store)
            target.calendar = calendar
            target.url = event.url
            target.title = event.title
            target.startDate = event.start
            target.endDate = event.end
            target.isAllDay = event.isAllDay
            target.notes = event.notes
            try? store.save(target, span: .thisEvent, commit: false)
        }
        for stale in existing.values {
            try? store.remove(stale, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }

    private func existingCalendar() -> EKCalendar? {
        defaults.string(forKey: Self.calendarIdKey).flatMap { store.calendar(withIdentifier: $0) }
    }

    private func sharpitCalendar() -> EKCalendar? {
        if let calendar = existingCalendar() { return calendar }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local })
        else { return nil }
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
            defaults.set(calendar.calendarIdentifier, forKey: Self.calendarIdKey)
            return calendar
        } catch {
            return nil
        }
    }
}
