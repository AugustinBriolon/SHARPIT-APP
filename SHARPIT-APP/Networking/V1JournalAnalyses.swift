import Foundation

/// `/api/v1/journal/analyses` — what the journal's habits go with: nights, recovery and Body
/// Battery read on the days a habit was noted against the days it was not.
///
/// Every word and every position is the server's (the web's `buildJournalHabitReading` and
/// `buildJournalAnalysesViewModel`): the app computes no statistic and formats no figure. An
/// association is not a cause, and the page says so.
nonisolated struct V1JournalAnalyses: Decodable, Sendable, Equatable {
    let minDays: Int
    let daysWithSignal: Int
    let daysInSpan: Int
    /// Nil until `minDays` days carry a journal signal.
    let reading: V1JournalAnalysesReading?
    /// Net associations where the habit goes with better nights or recovery.
    let lifts: [V1JournalAnalysesDomain]
    /// Net associations where the habit goes with worse ones.
    let drags: [V1JournalAnalysesDomain]
    /// Habits whose every association is still weak.
    let leads: [V1JournalAnalysesDomain]

    init(
        minDays: Int,
        daysWithSignal: Int,
        daysInSpan: Int = 0,
        reading: V1JournalAnalysesReading? = nil,
        lifts: [V1JournalAnalysesDomain] = [],
        drags: [V1JournalAnalysesDomain] = [],
        leads: [V1JournalAnalysesDomain] = []
    ) {
        self.minDays = minDays
        self.daysWithSignal = daysWithSignal
        self.daysInSpan = daysInSpan
        self.reading = reading
        self.lifts = lifts
        self.drags = drags
        self.leads = leads
    }

    private enum CodingKeys: String, CodingKey {
        case minDays, daysWithSignal, daysInSpan, reading, lifts, drags, leads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minDays = try container.decode(Int.self, forKey: .minDays)
        daysWithSignal = try container.decode(Int.self, forKey: .daysWithSignal)
        daysInSpan = try container.decodeIfPresent(Int.self, forKey: .daysInSpan) ?? 0
        reading = try container.decodeIfPresent(V1JournalAnalysesReading.self, forKey: .reading)
        lifts = try container.decodeIfPresent([V1JournalAnalysesDomain].self, forKey: .lifts) ?? []
        drags = try container.decodeIfPresent([V1JournalAnalysesDomain].self, forKey: .drags) ?? []
        leads = try container.decodeIfPresent([V1JournalAnalysesDomain].self, forKey: .leads) ?? []
    }

    var isReady: Bool { reading != nil }

    /// Days still to note before the analyses open.
    var remainingDays: Int { max(0, minDays - daysWithSignal) }

    var hasAssociations: Bool { !lifts.isEmpty || !drags.isEmpty || !leads.isEmpty }
}

nonisolated struct V1JournalAnalysesReading: Decodable, Sendable, Equatable {
    let headline: String
    /// One sentence naming the lever and its size.
    let verdict: String
    /// « 29 jours analysés · 2 associations nettes · 1 à confirmer ».
    let summary: String
    let actionHint: String
    let strengths: [String]
}

nonisolated struct V1JournalAnalysesDomain: Decodable, Sendable, Equatable, Identifiable {
    nonisolated enum Outcome: String, Decodable, Sendable {
        case sleepMinutes, recoveryScore, bodyBattery

        var symbol: String {
            switch self {
            case .sleepMinutes: "moon"
            case .recoveryScore: "heart"
            case .bodyBattery: "bolt"
            }
        }
    }

    nonisolated struct Tick: Decodable, Sendable, Equatable {
        let label: String
        let pct: Double
    }

    let outcome: Outcome
    let title: String
    let ticks: [Tick]
    let rows: [V1JournalAnalysesRow]

    var id: String { outcome.rawValue }
}

nonisolated struct V1JournalAnalysesRow: Decodable, Sendable, Equatable, Identifiable {
    let key: String
    let habit: String
    /// « mesure +1 j » when the outcome is read the day after; nil the same day.
    let lagLabel: String?
    /// Below the net threshold: a lead to confirm, drawn dashed.
    let weak: Bool
    let withoutLabel: String
    let withLabel: String
    /// « −52′ », « +8 ».
    let deltaLabel: String
    let mediansLabel: String
    let overlapSentence: String
    /// 0–100 on the domain's axis.
    let withoutPct: Double
    let withPct: Double
    let withDaysPct: [Double]
    let withoutDaysPct: [Double]
    let nYes: Int
    let nNo: Int

    var id: String { key }
}

nonisolated protocol JournalAnalysesServing: Sendable {
    func journalAnalyses(token: String) async throws -> V1JournalAnalyses
}
