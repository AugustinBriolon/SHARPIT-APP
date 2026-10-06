import Foundation
import Observation

/// Activité → Records: the athlete's best performances, read from `/api/v1/records`.
///
/// Owned by `ActivityView`, so reopening the page shows the records at once and refreshes them
/// quietly — a refresh that fails keeps what is on screen.
@MainActor
@Observable
final class RecordsStore {
    enum Phase: Equatable {
        case loading
        case loaded(V1Records)
        case failed(String)
        case unauthorized
    }

    private(set) var phase: Phase = .loading
    private(set) var isRefreshing = false

    private let client: any RecordsServing
    private let tokenProvider: () async throws -> String

    init(client: any RecordsServing = RecordsClient(), tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    var records: V1Records? {
        if case .loaded(let records) = phase { return records }
        return nil
    }

    func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let token = try await tokenProvider()
            let fresh = try await client.records(token: token)
            if records != fresh { phase = .loaded(fresh) }
        } catch is CancellationError {
            return
        } catch SharpitAPIError.unauthorized {
            phase = .unauthorized
        } catch {
            // Records already shown stay; only a page with nothing yet says it failed.
            if records == nil {
                phase = .failed(SharpitErrorGuidance.message(for: error, subject: "Le tableau des records"))
            }
        }
    }
}

/// How a record reads, in the web's words (`records-panel.tsx`).
nonisolated enum RecordsReadout {
    private static let french = Locale(identifier: "fr_FR")

    /// A record set in the last two weeks carries « Nouveau ».
    static func isRecent(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let days = dayCount(from: date, to: now, calendar: calendar)
        return days >= 0 && days <= 14
    }

    /// « 4:12/km · 3 mars 2026 », or the date alone.
    static func meta(_ entry: V1RecordEntry) -> String {
        let date = entry.date.formatted(.dateTime.day().month(.abbreviated).year().locale(french))
        guard let sublabel = entry.sublabel, !sublabel.isEmpty else { return date }
        return "\(sublabel) · \(date)"
    }

    /// « il y a 3 mois » up to four months, « record de la saison » within the year, then
    /// « il y a 2 ans » — the web's `recordNarrative`.
    static func narrative(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = dayCount(from: date, to: now, calendar: calendar)
        if days > 120 && days <= 365 { return "record de la saison" }
        return ago(days: days)
    }

    /// « Top 5 par catégorie sur 214 séances (180 avec données détaillées). »
    static func summary(_ records: V1Records) -> String {
        let sessions = records.totalActivities == 1 ? "1 séance" : "\(records.totalActivities) séances"
        return "Top 5 par catégorie sur \(sessions) (\(records.streamsAnalyzed) avec données détaillées)."
    }

    /// « 312 W ».
    static func watts(_ value: Double) -> String {
        "\(Int(value.rounded())) W"
    }

    static func ago(days: Int) -> String {
        switch days {
        case ..<1: return "aujourd'hui"
        case 1: return "hier"
        case 2..<30: return "il y a \(days) jours"
        case 30..<365:
            let months = max(1, Int((Double(days) / 30.4).rounded()))
            return "il y a \(months) mois"
        default:
            let years = max(1, Int((Double(days) / 365).rounded()))
            return years == 1 ? "il y a 1 an" : "il y a \(years) ans"
        }
    }

    static func dayCount(from date: Date, to now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    }
}
