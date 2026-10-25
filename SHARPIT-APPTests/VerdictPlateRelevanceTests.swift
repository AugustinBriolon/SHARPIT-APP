import Foundation
import Testing
import UIKit
import SwiftUI
@testable import Sharpit

private func decodeFold(_ verdictExtras: String) throws -> TodayFold {
    let json = """
    {
      "apiVersion": 1, "trainingDayId": "2026-10-25", "empty": null,
      "verdict": {
        "eyebrow": "Ce matin", "headline": "Journée légère", "subline": "",
        "posture": "steady", "statusLabel": "Facile",
        \(verdictExtras)
      },
      "weather": null, "sessions": [], "signals": []
    }
    """
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: Data(json.utf8))
    return TodayFoldMapper.map(response)
}

private func plate(
    limiters: [LimiterSignalCode] = [],
    supports: [SupportSignalCode] = [],
    tier: V1TodayPackTier? = .full,
    gaps: [String] = []
) -> InkPlateModel {
    InkPlateModel(
        statusLabel: "Facile", headline: "", actionLine: nil, limitingCause: nil,
        confidencePct: nil, confidenceLabel: nil, packTier: tier, estimationGaps: gaps,
        posture: .steady, limiterSignals: limiters, supportSignals: supports
    )
}

@Test func foldMapsSupportsAndDropsUnknownCodes() throws {
    let fold = try decodeFold(#""supportSignals": ["subjective_ok", "not_a_code", "hrv_ok"]"#)
    #expect(fold.plate.supportSignals == [.subjectiveOk, .hrvOk])
}

@Test func yesterdayLabelShowsOnlyWhenTheVerdictChanged() throws {
    let changed = try decodeFold(#""vsYesterday": "changed", "vsYesterdayVerdictLabel": "Hier : Prudence""#)
    #expect(changed.plate.yesterdayLabel == "Hier : Prudence")
    let same = try decodeFold(#""vsYesterday": "same", "vsYesterdayVerdictLabel": "Hier : Facile""#)
    #expect(same.plate.yesterdayLabel == nil)
    let legacy = try decodeFold(#""vsYesterdayLabel": "Changé depuis hier""#)
    #expect(legacy.plate.yesterdayLabel == nil)
}

@Test func reasonsKeepTwoFreinsThenWhatHeldUpThreeAtMost() {
    let reasons = plate(
        limiters: [.hrvLow, .sleepShort, .loadElevated, .unknown("x")],
        supports: [.subjectiveOk, .rhrOk]
    ).reasons(isExpert: true)
    #expect(reasons.map(\.label) == ["VFC basse", "Sommeil court", "Ressenti élevé"])
    #expect(reasons.map(\.isSupport) == [false, false, true])
}

@Test func reasonsFillWithSupportsWhenNothingHoldsBack() {
    let reasons = plate(supports: [.hrvOk, .sleepAdequate]).reasons(isExpert: false)
    #expect(reasons.map(\.label) == ["Corps bien récupéré", "Nuit suffisante"])
}

@Test func estimationNoteSpeaksOnlyWhenTheReadingIsPartial() {
    #expect(plate(tier: .full, gaps: ["x"]).estimationNote == nil)
    #expect(plate(tier: nil).estimationNote == nil)
    #expect(plate(tier: .partial).estimationNote == "Estimation partielle")
    #expect(
        plate(tier: .low, gaps: ["Baseline VFC partielle (moins de 14 j)"]).estimationNote
            == "Estimation partielle · Baseline VFC partielle (moins de 14 j)"
    )
    #expect(plate(tier: .insufficient).estimationNote == "Données insuffisantes pour un verdict fiable")
}

@MainActor
@Test(arguments: [UIUserInterfaceStyle.light, .dark])
func verdictPlateReadsStateDecisionWhyAndFacts(style: UIUserInterfaceStyle) async throws {
    var model = plate(
        limiters: [.hrvLow, .sleepShort],
        supports: [.subjectiveOk],
        tier: .partial,
        gaps: ["Baseline VFC partielle (moins de 14 j)"]
    )
    model.statusLabel = "Repos"
    model.stateCode = .recover
    model.showHeadline = false
    model.instruction = "Privilégie le repos ou une marche très légère."
    model.explanationEssential = "Ta forme ressentie est bonne, mais ton corps n’a pas encore récupéré et ta nuit a été trop courte."
    model.yesterdayLabel = "Hier : Prudence"
    try await assertSnapshot(
        InkVerdictPlate(plate: model).padding(16).background(SharpitCanvasBackground()),
        named: "verdict-plate",
        style: style
    )
}
