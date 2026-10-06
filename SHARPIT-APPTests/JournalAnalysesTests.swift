import Foundation
import Testing
@testable import Sharpit

// What `/api/v1/journal/analyses` answers once enough days are noted (the web's projection).
private nonisolated let readyJSON = #"""
{"apiVersion": 1, "minDays": 7, "daysWithSignal": 29, "daysInSpan": 31, "reading": {"headline": "2 associations nettes · pistes à confirmer", "verdict": "Ton levier le plus net : « Alcool », 52 minutes de sommeil en moins.", "summary": "29 jours analysés · 2 associations nettes · 1 à confirmer", "actionHint": "Teste 7 jours sans « Alcool » (ou en réduisant), puis compare sommeil et récupération.", "strengths": ["Yoga · sommeil plus haut"]}, "lifts": [{"outcome": "sleepMinutes", "title": "Sommeil", "ticks": [{"label": "5 h 30", "pct": 0}, {"label": "6 h 30", "pct": 33.3}, {"label": "7 h 30", "pct": 66.7}, {"label": "8 h 30", "pct": 100}], "rows": [{"key": "yoga:plus:sleepMinutes", "habit": "Yoga", "lagLabel": null, "weak": false, "withoutLabel": "7 h 00", "withLabel": "7 h 40", "deltaLabel": "+40′", "mediansLabel": "sans 7 h 00 → avec 7 h 40", "overlapSentence": "3 jours sur 3 avec l’habitude restent sous la médiane sans : l’écart est net, mais la règle n’est pas absolue.", "withoutPct": 50, "withPct": 72.2, "withDaysPct": [11.1, 23.3, 27.8], "withoutDaysPct": [52.2, 44.4, 61.1], "nYes": 7, "nNo": 22}]}], "drags": [{"outcome": "sleepMinutes", "title": "Sommeil", "ticks": [{"label": "5 h 30", "pct": 0}, {"label": "6 h 30", "pct": 33.3}, {"label": "7 h 30", "pct": 66.7}, {"label": "8 h 30", "pct": 100}], "rows": [{"key": "alcohol:minus:sleepMinutes", "habit": "Alcool", "lagLabel": "mesure +1 j", "weak": false, "withoutLabel": "7 h 04", "withLabel": "6 h 12", "deltaLabel": "−52′", "mediansLabel": "sans 7 h 04 → avec 6 h 12", "overlapSentence": "Les 3 jours avec l’habitude sont tous sous la médiane sans : l’écart est net et régulier.", "withoutPct": 52.2, "withPct": 23.3, "withDaysPct": [11.1, 23.3, 27.8], "withoutDaysPct": [52.2, 44.4, 61.1], "nYes": 7, "nNo": 22}]}], "leads": [{"outcome": "recoveryScore", "title": "Récupération", "ticks": [{"label": "30", "pct": 0}, {"label": "50", "pct": 33.3}, {"label": "70", "pct": 66.7}, {"label": "90", "pct": 100}], "rows": [{"key": "late_meal:minus:recoveryScore", "habit": "Repas tardif", "lagLabel": null, "weak": true, "withoutLabel": "60", "withLabel": "52", "deltaLabel": "−8", "mediansLabel": "sans 60 → avec 52", "overlapSentence": "Les 2 jours avec l’habitude sont tous sous la médiane sans : l’écart reste à confirmer et régulier.", "withoutPct": 50, "withPct": 36.7, "withDaysPct": [33.3, 36.7], "withoutDaysPct": [50, 53.3], "nYes": 7, "nNo": 22}]}]}
"""#

private nonisolated let notReadyJSON = """
{ "apiVersion": 1, "minDays": 7, "daysWithSignal": 4, "daysInSpan": 5,
  "reading": null, "lifts": [], "drags": [], "leads": [] }
"""

private func decode(_ json: String) throws -> V1JournalAnalyses {
    try JSONDecoder().decode(V1JournalAnalyses.self, from: Data(json.utf8))
}

private actor StubJournalAnalyses: JournalAnalysesServing {
    var answers: [Result<V1JournalAnalyses, SharpitAPIError>]

    init(_ answers: [Result<V1JournalAnalyses, SharpitAPIError>]) {
        self.answers = answers
    }

    func journalAnalyses(token: String) async throws -> V1JournalAnalyses {
        try answers.removeFirst().get()
    }
}

@Suite struct JournalAnalysesTests {
    @Test func readsTheVerdictAndSortsTheAssociations() throws {
        let analyses = try decode(readyJSON)
        #expect(analyses.isReady)
        #expect(analyses.reading?.verdict == "Ton levier le plus net : « Alcool », 52 minutes de sommeil en moins.")
        #expect(analyses.reading?.strengths == ["Yoga · sommeil plus haut"])
        #expect(analyses.lifts.first?.rows.first?.habit == "Yoga")
        #expect(analyses.drags.first?.outcome == .sleepMinutes)
        #expect(analyses.drags.first?.rows.first?.lagLabel == "mesure +1 j")
        #expect(analyses.leads.first?.rows.first?.weak == true)
        #expect(analyses.leads.first?.ticks.map(\.label) == ["30", "50", "70", "90"])
    }

    @Test func staysClosedUntilEnoughDaysAreNoted() throws {
        let analyses = try decode(notReadyJSON)
        #expect(!analyses.isReady)
        #expect(analyses.remainingDays == 3)
        #expect(JournalAnalysesReadout.progress(analyses) == "4 / 7 jours · encore 3")
        #expect(!analyses.hasAssociations)
    }

    @Test func aRowSaysHowManyDaysItStandsOn() throws {
        let row = try #require(try decode(readyJSON).drags.first?.rows.first)
        #expect(JournalAnalysesReadout.sample(row) == "7 jours avec · 22 sans")
    }

    @MainActor @Test func aFailedRefreshKeepsTheReadingShown() async throws {
        let ready = try decode(readyJSON)
        let store = JournalAnalysesStore(
            client: StubJournalAnalyses([.success(ready), .failure(SharpitAPIError.server)]),
            tokenProvider: { "token" }
        )
        await store.load()
        await store.load()
        #expect(store.phase == .loaded(ready))
    }

    @MainActor @Test func aFirstReadThatFailsSaysSo() async {
        let store = JournalAnalysesStore(
            client: StubJournalAnalyses([.failure(SharpitAPIError.transport)]),
            tokenProvider: { "token" }
        )
        await store.load()
        guard case .failed = store.phase else {
            Issue.record("expected a failure, got \(store.phase)")
            return
        }
    }
}
