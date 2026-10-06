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

/// Effort and Adaptation carry no per-day history of their own: the picker's marks come
/// from `/api/v1/data-days` alone.
nonisolated extension V1EffortResponse: V1DayResource {
    var dataByDay: [String: Bool] { [:] }
}

nonisolated extension V1AdaptationResponse: V1DayResource {
    var dataByDay: [String: Bool] { [:] }
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

    /// Days with data read ahead after the first load.
    static var prefetchCount: Int { 6 }

    private(set) var phase: Phase = .loading
    /// The day on screen. Changing it goes through `select(_:)`.
    private(set) var selectedDay: Date
    /// True while another day loads over the one on screen, which stays until it arrives.
    private(set) var isSwitchingDay = false
    /// Which days hold data: from the data-days read, then every payload's own history. A day
    /// outside all of them is simply unknown.
    var dataByDay: [String: Bool] { marker?.byDay ?? payloadDays }

    private let fetch: @Sendable (_ trainingDayId: String, _ token: String) async throws -> Payload
    /// Reads the picker's history; nil for a screen without a data-days domain.
    private let marker: DataDaysMarker?
    /// What payloads said about days, for a screen without a marker.
    private var payloadDays: [String: Bool] = [:]
    private let tokenProvider: () async throws -> String
    private var trainingDayId: String { TrainingDayId.today(now: selectedDay) }
    private let failureMessage: String
    private var cache: [String: Payload] = [:]
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
        marker = dataDays.map { DataDaysMarker(tokenProvider: tokenProvider, fetch: $0) }
        self.fetch = fetch
    }

    /// Nil when the day is outside every range read so far.
    func hasData(on day: Date) -> Bool? {
        dataByDay[TrainingDayId.today(now: day)]
    }

    func load() async {
        await load(keepingDayOnFailure: true)
        await marker?.ensure(around: selectedDay)
        prefetchRecentDays()
    }

    /// Reads the marks of the weeks the strip or the calendar is about to show.
    func markDays(around day: Date) async {
        await marker?.ensure(around: day)
    }

    /// After fresh data came in (a sync): forgets every day read and every mark, then reads again.
    func reloadAll() async {
        prefetchTask?.cancel()
        prefetchTask = nil
        cache = [:]
        marker?.reset()
        payloadDays = [:]
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
            for (dayId, hasData) in payload.dataByDay {
                if let marker { marker.note(dayId, hasData: hasData) } else { payloadDays[dayId] = hasData }
            }
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
