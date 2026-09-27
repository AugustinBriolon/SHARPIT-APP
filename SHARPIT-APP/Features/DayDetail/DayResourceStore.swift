import Foundation
import Observation

/// A v1 resource read for one training day, which may come back empty.
nonisolated protocol V1DayResource: Decodable, Equatable, Sendable {
    var empty: V1DayEmpty? { get }
    /// Whether each day of the payload's history carried data, by training day id.
    var dataByDay: [String: Bool] { get }
}

nonisolated extension V1SleepResponse: V1DayResource {
    var dataByDay: [String: Bool] {
        Dictionary(history.map { ($0.date, $0.minutes != nil) }, uniquingKeysWith: { $1 })
    }
}

nonisolated extension V1RecoveryResponse: V1DayResource {
    var dataByDay: [String: Bool] {
        Dictionary(history.map { ($0.date, $0.hrv != nil || $0.restingHr != nil) }, uniquingKeysWith: { $1 })
    }
}

/// Loads one day of a drill-down resource — the night behind the sleep score, the signals
/// behind readiness, the day's food log. The screens differ; how they load and fail does not.
///
/// A day read once is kept for the life of the screen, so going back to it is instant and it
/// refreshes behind what is shown. The days that hold data are asked for on the first load
/// (`/api/v1/data-days`), so the picker marks them before any is opened, and the few most recent
/// of them are read ahead, so tapping one does not wait on the network.
@MainActor
@Observable
final class DayResourceStore<Payload: V1DayResource> {
    enum Phase: Equatable {
        case loading
        case loaded(Payload)
        case empty(V1DayEmpty)
        case failed(String)
        case unauthorized
    }

    /// How far back the picker's marks reach: its 26 weeks, in the route's 92-day windows.
    static var markedWindows: Int { 2 }
    static var markedWindowDays: Int { 91 }
    /// Days with data read ahead after the first load.
    static var prefetchCount: Int { 6 }

    private(set) var phase: Phase = .loading
    /// The day on screen. Changing it goes through `select(_:)`.
    private(set) var selectedDay: Date
    /// True while another day loads over the one on screen, which stays until it arrives.
    private(set) var isSwitchingDay = false
    /// Which days hold data: from the data-days read, then every payload's own history. A day
    /// outside all of them is simply unknown.
    private(set) var dataByDay: [String: Bool] = [:]

    private let fetch: @Sendable (_ trainingDayId: String, _ token: String) async throws -> Payload
    private let fetchDataDays: (@Sendable (_ from: String, _ to: String, _ token: String) async throws -> [String])?
    private let tokenProvider: () async throws -> String
    private var trainingDayId: String { TrainingDayId.today(now: selectedDay) }
    private let failureMessage: String
    private var cache: [String: Payload] = [:]
    private var hasMarkedDays = false
    private var prefetchTask: Task<Void, Never>?

    init(
        failureMessage: String,
        tokenProvider: @escaping () async throws -> String,
        day: Date = .now,
        dataDays: (@Sendable (_ from: String, _ to: String, _ token: String) async throws -> [String])? = nil,
        fetch: @escaping @Sendable (_ trainingDayId: String, _ token: String) async throws -> Payload
    ) {
        self.failureMessage = failureMessage
        self.tokenProvider = tokenProvider
        selectedDay = day
        fetchDataDays = dataDays
        self.fetch = fetch
    }

    /// Nil when the day is outside every range read so far.
    func hasData(on day: Date) -> Bool? {
        dataByDay[TrainingDayId.today(now: day)]
    }

    func load() async {
        await load(keepingDayOnFailure: true)
        await markDataDaysIfNeeded()
        prefetchRecentDays()
    }

    /// After fresh data came in (a sync): forgets every day read and every mark, then reads again.
    func reloadAll() async {
        prefetchTask?.cancel()
        prefetchTask = nil
        cache = [:]
        hasMarkedDays = false
        await load()
    }

    /// Shows another day. A day already read appears at once and refreshes behind; otherwise
    /// the current one stays on screen, dimmed, until the new one arrives — and a failure then
    /// says so rather than leaving the old day under a new date.
    func select(_ day: Date) async {
        guard !Calendar.current.isDate(day, inSameDayAs: selectedDay) else { return }
        selectedDay = day
        if let cached = cache[trainingDayId] {
            show(cached)
            await load(keepingDayOnFailure: true)
            return
        }
        isSwitchingDay = true
        defer { isSwitchingDay = false }
        await load(keepingDayOnFailure: false)
    }

    /// The cause and what to do for a network or session failure; the screen's own words otherwise.
    static func failure(_ error: Error, fallback: String) -> String {
        switch error as? SharpitAPIError {
        case .transport?, .rateLimited?: SharpitErrorGuidance.message(for: error, subject: "")
        default: "\(fallback) Réessaie dans un instant."
        }
    }

    private func show(_ payload: Payload) {
        phase = payload.empty.map(Phase.empty) ?? .loaded(payload)
    }

    private func load(keepingDayOnFailure: Bool) async {
        let requestedDay = trainingDayId
        do {
            let token = try await tokenProvider()
            let payload = try await fetch(requestedDay, token)
            cache[requestedDay] = payload
            // A quicker answer for a day picked since must not be overwritten by this one.
            dataByDay.merge(payload.dataByDay) { _, new in new }
            guard requestedDay == trainingDayId else { return }
            show(payload)
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .unauthorized {
            phase = .unauthorized
        } catch {
            guard requestedDay == trainingDayId else { return }
            if keepingDayOnFailure, case .loaded = phase { return }
            phase = .failed(Self.failure(error, fallback: failureMessage))
        }
    }

    /// Marks the picker's whole range once: every day in it is known, with data or without.
    private func markDataDaysIfNeeded() async {
        guard !hasMarkedDays, let fetchDataDays, let token = try? await tokenProvider() else { return }
        hasMarkedDays = true
        let calendar = Calendar.current
        var end = calendar.startOfDay(for: .now)
        var marks: [String: Bool] = [:]
        for _ in 0..<Self.markedWindows {
            guard let start = calendar.date(byAdding: .day, value: -Self.markedWindowDays, to: end) else { break }
            let from = TrainingDayId.today(now: start)
            let to = TrainingDayId.today(now: end)
            guard let days = try? await fetchDataDays(from, to, token) else { break }
            var day = start
            while day <= end {
                marks[TrainingDayId.today(now: day)] = false
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            for id in days { marks[id] = true }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: start) else { break }
            end = previous
        }
        // What a payload already said about a day is newer than the range read.
        dataByDay = marks.merging(dataByDay) { _, known in known }
    }

    /// Reads the most recent days with data ahead of the athlete, one at a time.
    private func prefetchRecentDays() {
        guard prefetchTask == nil else { return }
        let ahead = dataByDay
            .filter { $0.value && cache[$0.key] == nil }
            .map(\.key)
            .sorted(by: >)
            .prefix(Self.prefetchCount)
        guard !ahead.isEmpty else { return }
        prefetchTask = Task { [weak self] in
            for dayId in ahead {
                guard let self, !Task.isCancelled else { return }
                guard let token = try? await self.tokenProvider(),
                      let payload = try? await self.fetch(dayId, token)
                else { continue }
                self.cache[dayId] = payload
            }
        }
    }
}
