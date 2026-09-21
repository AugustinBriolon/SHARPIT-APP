import Foundation
import Observation

/// A v1 resource read for one training day, which may come back empty.
nonisolated protocol V1DayResource: Decodable, Equatable, Sendable {
    var empty: V1DayEmpty? { get }
}

extension V1SleepResponse: V1DayResource {}
extension V1RecoveryResponse: V1DayResource {}

/// Loads one day of a drill-down resource — the night behind the sleep score, the signals
/// behind readiness. The screens differ; how they load and fail does not.
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

    private(set) var phase: Phase = .loading
    /// The day on screen. Changing it goes through `select(_:)`.
    private(set) var selectedDay: Date
    /// True while another day loads over the one on screen, which stays until it arrives.
    private(set) var isSwitchingDay = false

    private let fetch: @Sendable (_ trainingDayId: String, _ token: String) async throws -> Payload
    private let tokenProvider: () async throws -> String
    private var trainingDayId: String { TrainingDayId.today(now: selectedDay) }
    private let failureMessage: String

    init(
        failureMessage: String,
        tokenProvider: @escaping () async throws -> String,
        day: Date = .now,
        fetch: @escaping @Sendable (_ trainingDayId: String, _ token: String) async throws -> Payload
    ) {
        self.failureMessage = failureMessage
        self.tokenProvider = tokenProvider
        selectedDay = day
        self.fetch = fetch
    }

    func load() async {
        await load(keepingDayOnFailure: true)
    }

    /// Shows another day. The current one stays on screen, dimmed, until the new one
    /// arrives — and a failure then says so rather than leaving the old day under a new date.
    func select(_ day: Date) async {
        guard !Calendar.current.isDate(day, inSameDayAs: selectedDay) else { return }
        selectedDay = day
        isSwitchingDay = true
        defer { isSwitchingDay = false }
        await load(keepingDayOnFailure: false)
    }

    private func load(keepingDayOnFailure: Bool) async {
        let requestedDay = trainingDayId
        do {
            let token = try await tokenProvider()
            let payload = try await fetch(requestedDay, token)
            // A quicker answer for a day picked since must not be overwritten by this one.
            guard requestedDay == trainingDayId else { return }
            phase = payload.empty.map(Phase.empty) ?? .loaded(payload)
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .unauthorized {
            phase = .unauthorized
        } catch {
            guard requestedDay == trainingDayId else { return }
            if keepingDayOnFailure, case .loaded = phase { return }
            phase = .failed(failureMessage)
        }
    }
}
