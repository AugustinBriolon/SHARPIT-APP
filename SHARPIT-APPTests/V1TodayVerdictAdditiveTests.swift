import Foundation
import Testing
@testable import Sharpit

@Test func additiveVerdictFieldsDecodeWithoutBreakingLegacy() throws {
    let legacy = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    #expect(legacy.verdict.explanation == nil)
    #expect(legacy.verdict.instruction == nil)
    #expect(legacy.verdict.limiterSignals == nil)
    #expect(legacy.verdict.stateCode == nil)
    #expect(legacy.verdict.showHeadline == nil)
    #expect(legacy.verdict.statusLabel == "FEU VERT")
}

@Test func additiveVerdictFieldsDecodeFromNewPayload() throws {
    let json = """
    {
      "apiVersion": 1,
      "trainingDayId": "2026-10-15",
      "empty": null,
      "verdict": {
        "eyebrow": "Ce matin",
        "headline": "Priorité au repos",
        "subline": "legacy",
        "posture": "protect",
        "confidencePct": 60,
        "limitingCause": "Sommeil",
        "statusLabel": "Repos",
        "actionLine": "legacy action",
        "confidenceLabel": "ESTIMATION PARTIELLE",
        "packTier": "PARTIAL",
        "estimationGaps": [],
        "explanation": {
          "essential": "Ton corps n’a pas encore récupéré.",
          "expert": "VFC basse et sommeil court."
        },
        "instruction": "Privilégie le repos ou une marche très légère.",
        "limiterSignal": "hrv_low",
        "limiterSignals": ["hrv_low", "sleep_short", "not_a_real_code"],
        "vsYesterdayLabel": "Changé depuis hier",
        "showHeadline": false,
        "stateCode": "RECOVER"
      },
      "weather": null,
      "sessions": [],
      "signals": []
    }
    """
    let data = try #require(json.data(using: .utf8))
    let decoded = try JSONDecoder().decode(V1TodayResponse.self, from: data)
    let verdict = decoded.verdict

    #expect(verdict.statusLabel == "Repos")
    #expect(verdict.showHeadline == false)
    #expect(verdict.stateCode == .recover)
    #expect(verdict.instruction == "Privilégie le repos ou une marche très légère.")
    #expect(verdict.explanation?.essential == "Ton corps n’a pas encore récupéré.")
    #expect(verdict.explanation?.expert == "VFC basse et sommeil court.")
    #expect(verdict.vsYesterdayLabel == "Changé depuis hier")
    #expect(verdict.limiterSignal == .hrvLow)
    #expect(verdict.limiterSignals == [.hrvLow, .sleepShort, .unknown("not_a_real_code")])
}

@Test func foldMapsAdditiveVerdictForPlate() throws {
    let json = """
    {
      "apiVersion": 1,
      "trainingDayId": "2026-10-15",
      "empty": null,
      "verdict": {
        "eyebrow": "Ce matin",
        "headline": "Priorité au repos",
        "subline": "legacy",
        "posture": "protect",
        "statusLabel": "Repos",
        "actionLine": "legacy",
        "explanation": { "essential": "Essentiel.", "expert": "Expert." },
        "instruction": "Privilégie le repos.",
        "limiterSignals": ["subjective_low"],
        "vsYesterdayLabel": "Comme hier",
        "showHeadline": false,
        "stateCode": "RECOVER"
      },
      "weather": null,
      "sessions": [],
      "signals": []
    }
    """
    let data = try #require(json.data(using: .utf8))
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: data)
    let plate = TodayFoldMapper.map(response).plate

    #expect(plate.statusLabel == "Repos")
    #expect(plate.vsYesterdayLabel == "Comme hier")
    #expect(plate.showHeadline == false)
    #expect(plate.stateCode == .recover)
    #expect(plate.instruction == "Privilégie le repos.")
    #expect(plate.explanationEssential == "Essentiel.")
    #expect(plate.explanationExpert == "Expert.")
    #expect(plate.limiterSignals == [.subjectiveLow])
}
