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

/// Apple Calendar write + pull-back when `apple-calendar` is the calendar primary (SharpIt Pro).
@MainActor
final class AppleCalendarSync {
    static let shared = AppleCalendarSync()

    static let providerId = "apple-calendar"
    static let calendarClassId = "calendar"
    static let enabledKey = "planCalendarSync.enabled"
    static let writeCalendarIdKey = "appleCalendar.writeCalendarId"
    private static let legacyCalendarIdKey = "planCalendarSync.calendarId"
    static let calendarTitle = "SharpIt"

    private let store = EKEventStore()
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        migrateWriteCalendarIdIfNeeded()
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    var writeCalendarIdentifier: String? {
        get { defaults.string(forKey: Self.writeCalendarIdKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.writeCalendarIdKey)
            } else {
                defaults.removeObject(forKey: Self.writeCalendarIdKey)
            }
        }
    }

    /// Asks iOS for the calendar, then turns the copy on. False when the athlete refused.
    func enable() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        defaults.set(granted, forKey: Self.enabledKey)
        return granted
    }

    /// Turns the copy off and removes the SharpIt calendar with every event it held.
    func disable() {
        defaults.set(false, forKey: Self.enabledKey)
        if let calendar = existingWriteCalendar(), calendar.title == Self.calendarTitle {
            try? store.removeCalendar(calendar, commit: true)
        }
        writeCalendarIdentifier = nil
        defaults.removeObject(forKey: Self.legacyCalendarIdKey)
    }

    func refresh(
        isPro: Bool,
        plan: any PlannedSessionServing,
        tokenProvider: () async throws -> String,
        sourcePrefsClient: any SourcePrefsServing = SharpitClient(),
        sessionWriter: (any PlannedSessionMutating)? = nil,
        busyClient: (any AppleCalendarBusyServing)? = nil,
        calendarLinker: (any AppleCalendarLinking)? = nil,
        now: Date = .now
    ) async {
        guard isPro, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: PlanCalendarPlanner.horizonDays, to: start) ?? now
        do {
            let token = try await tokenProvider()
            let prefsAnswer = try await sourcePrefsClient.sourcePrefs(token: token)
            if Self.shouldUploadBusy(prefs: prefsAnswer.prefs, connected: prefsAnswer.connected) {
                await uploadBusy(from: start, to: end, client: busyClient, token: token)
            }
            guard isEnabled, Self.shouldWrite(prefs: prefsAnswer.prefs, connected: prefsAnswer.connected) else { return }
            _ = try? await calendarLinker?.linkAppleCalendar(true, token: token)
            var sessions = try await plan.plannedSessions(from: start, to: end, token: token)
            guard let writeCalendar = writeCalendar() else { return }
            if let sessionWriter {
                sessions = await pullBack(
                    sessions: sessions,
                    writeCalendar: writeCalendar,
                    from: start,
                    to: end,
                    writer: sessionWriter,
                    token: token
                )
            }
            apply(PlanCalendarPlanner.events(for: sessions, calendar: calendar), to: writeCalendar, from: start, to: end)
        } catch {
            // Offline or signed out: the calendar keeps what it holds.
        }
    }

    static func shouldWrite(prefs: V1SourcePrefs, connected: [String]) -> Bool {
        guard connected.contains(providerId) else { return false }
        let slot = prefs.sources(for: calendarClassId)
        guard slot.enabled.contains(providerId) else { return false }
        return slot.primary == providerId
    }

    static func shouldUploadBusy(prefs: V1SourcePrefs, connected: [String]) -> Bool {
        connected.contains(providerId) && prefs.sources(for: calendarClassId).enabled.contains(providerId)
    }

    private func pullBack(
        sessions: [V1PlannedSessionItem],
        writeCalendar: EKCalendar,
        from start: Date,
        to end: Date,
        writer: any PlannedSessionMutating,
        token: String
    ) async -> [V1PlannedSessionItem] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [writeCalendar])
        let existing = Dictionary(
            store.events(matching: predicate).compactMap { event in event.url.map { ($0, event) } },
            uniquingKeysWith: { first, _ in first }
        )
        var updated = sessions
        for (index, session) in sessions.enumerated() {
            guard let planStart = AppleCalendarPull.planStart(for: session, calendar: calendar) else { continue }
            let url = PlanCalendarPlanner.url(for: session.id)
            guard let ekEvent = existing[url] else { continue }
            let resolved = AppleCalendarPull.resolveStart(plan: planStart, event: ekEvent.startDate)
            guard AppleCalendarPull.scheduleDiffers(plan: planStart, resolved: resolved) else { continue }
            let fields = AppleCalendarPull.patchFields(
                matching: resolved,
                isAllDay: ekEvent.isAllDay,
                calendar: calendar
            )
            guard !fields.isEmpty else { continue }
            if let patched = try? await writer.updateSession(id: session.id, fields: fields, token: token) {
                updated[index] = patched
            }
        }
        return updated
    }

    private func uploadBusy(
        from start: Date,
        to end: Date,
        client: (any AppleCalendarBusyServing)?,
        token: String
    ) async {
        guard let client else { return }
        let intervals = busyIntervals(from: start, to: end)
        guard !intervals.isEmpty else { return }
        _ = try? await client.uploadAppleCalendarBusy(intervals, token: token)
    }

    private func busyIntervals(from start: Date, to end: Date) -> [V1CalendarBusyInterval] {
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let capped = store.events(matching: predicate).prefix(2_000)
        return capped.map {
            V1CalendarBusyInterval(
                start: formatter.string(from: $0.startDate),
                end: formatter.string(from: $0.endDate)
            )
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

    private func migrateWriteCalendarIdIfNeeded() {
        guard writeCalendarIdentifier == nil,
              let legacy = defaults.string(forKey: Self.legacyCalendarIdKey)
        else { return }
        writeCalendarIdentifier = legacy
    }

    private func existingWriteCalendar() -> EKCalendar? {
        writeCalendarIdentifier.flatMap { store.calendar(withIdentifier: $0) }
    }

    private func writeCalendar() -> EKCalendar? {
        if let calendar = existingWriteCalendar() { return calendar }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local })
        else { return nil }
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
            writeCalendarIdentifier = calendar.calendarIdentifier
            defaults.removeObject(forKey: Self.legacyCalendarIdKey)
            return calendar
        } catch {
            return nil
        }
    }
}

typealias PlanCalendarSync = AppleCalendarSync
