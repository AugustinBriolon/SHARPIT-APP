import Foundation
import Observation

/// Reads Apple Health once and says, signal by signal, what it could replace.
@MainActor
@Observable
final class HealthCoverageStore {
    enum Phase: Equatable {
        case idle
        case reading
        case ready([HealthCoverageRow])
        case unavailable
        case failed(String)
    }

    static let windowDays = 14

    private(set) var phase: Phase = .idle

    private let reader: any HealthReading
    private let now: () -> Date

    init(reader: any HealthReading, now: @escaping () -> Date = Date.init) {
        self.reader = reader
        self.now = now
    }

    func run() async {
        guard reader.isAvailable else {
            phase = .unavailable
            return
        }
        phase = .reading
        do {
            try await reader.requestAuthorization()
        } catch {
            phase = .failed("Accès à Apple Santé refusé.")
            return
        }
        let since = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: now()) ?? now()
        var readings: [HealthSignal: HealthSignalReading] = [:]
        for signal in HealthSignal.allCases where signal.hasHealthEquivalent {
            readings[signal] = await reader.reading(for: signal, since: since)
        }
        phase = .ready(HealthCoverage.rows(readings: readings, windowDays: Self.windowDays))
    }
}
