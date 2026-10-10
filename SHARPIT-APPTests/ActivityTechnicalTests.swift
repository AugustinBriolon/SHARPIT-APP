import Foundation
import Testing
@testable import Sharpit

/// The web's `ActivityAnalysis`, as `/api/v1/activities/<id>/streams` sends it.
private let streamsJSON = #"""
{
  "available": true, "path": null, "samples": [], "stats": null,
  "has": { "hr": true },
  "analysis": {
    "thresholds": { "ftp": 250, "maxHr": 190, "lthr": 168, "runThresholdPaceSecPerKm": null, "source": "profile" },
    "load": { "tss": 82.4, "intensityFactor": 0.81, "method": "power" },
    "hr": {
      "zones": [
        { "id": "z1", "label": "Récupération", "shortLabel": "Z1", "color": "var(--color-chart-1)", "seconds": 600, "percent": 16.7 },
        { "id": "z2", "label": "Endurance", "shortLabel": "Z2", "color": "var(--color-chart-2)", "seconds": 3000, "percent": 83.3 }
      ],
      "decouplingPct": 6.2, "efficiencyFactor": 1.42, "efficiencyLabel": "EF (NP/FC)", "avgHr": 142, "maxHr": 171
    },
    "power": { "normalized": 212, "avg": 198, "variabilityIndex": 1.07, "intensityFactor": 0.81, "tss": 82, "zones": [] },
    "run": null,
    "bike": { "splits": [] }
  }
}
"""#

@Test func theStreamsCarryTheServersTechnicalReading() throws {
    let payload = try JSONDecoder().decode(V1ActivityStreamPayload.self, from: Data(streamsJSON.utf8))
    let analysis = try #require(payload.analysis)

    #expect(analysis.power?.normalized == 212)
    #expect(analysis.hr?.zones.map(\.shortLabel) == ["Z1", "Z2"])
    #expect(analysis.thresholds?.source == "profile")
}

@Test func theExpertRowsFollowTheWebsOrderAndWords() throws {
    let payload = try JSONDecoder().decode(V1ActivityStreamPayload.self, from: Data(streamsJSON.utf8))
    let rows = ActivityTechnicalReadout.rows(try #require(payload.analysis))

    #expect(rows.map(\.label) == ["NP", "IF", "VI", "TSS", "EF (NP/FC)", "Découplage"])
    #expect(rows[0].value == "212 W")
    #expect(rows[0].note == "moy 198 W")
    #expect(rows[1].value == "0,81")
    #expect(rows[1].note == "FTP 250 W")
    #expect(rows[2].note == "effort régulier")
    #expect(rows[3].value == "82")
    #expect(rows[5].value == "+6,2 %")
    #expect(rows[5].note == "Correct pour une sortie longue")
}

@Test func anEmptyZoneListIsNoDistribution() {
    #expect(ActivityTechnicalReadout.zones([]).isEmpty)
    #expect(ActivityTechnicalReadout.zones(nil).isEmpty)
}

@Test func theThresholdsSayWhereTheyCameFrom() {
    let analysis = V1ActivityAnalysis(thresholds: .init(ftp: 250, maxHr: nil, lthr: 168, source: "estimate"))

    #expect(ActivityTechnicalReadout.thresholdsLine(analysis) == "FTP 250 W · LTHR 168 bpm · seuils estimés")
}

@Test func aPayloadWithoutAnalysisStillDecodes() throws {
    let json = #"{ "available": true, "path": null, "samples": [], "stats": null }"#
    let payload = try JSONDecoder().decode(V1ActivityStreamPayload.self, from: Data(json.utf8))

    #expect(payload.analysis == nil)
}

// MARK: - Training load

@Test func theTrainingLoadDecodesTheServersProjection() throws {
    let json = #"""
    { "apiVersion": 1, "trainingDayId": "2026-09-29",
      "days": [ { "date": "2026-09-29", "tss": 80, "ctl": 52.4, "atl": 61.8, "tsb": -9.4 } ],
      "weeks": [ { "weekEnd": "2026-09-22", "tss": 310 }, { "weekEnd": "2026-09-29", "tss": 140 } ] }
    """#
    let load = try JSONDecoder().decode(V1TrainingLoad.self, from: Data(json.utf8))

    #expect(load.days.last?.ctl == 52.4)
    #expect(load.weeks.map(\.tss) == [310, 140])
}

@Test func netFormReadsSignedAndAgainstTheWebsBand() {
    #expect(TrainingLoadReadout.signed(-9.4) == "−9")
    #expect(TrainingLoadReadout.signed(4.6) == "+5")
    #expect(TrainingLoadReadout.signed(0.2) == "0")
    #expect(TrainingLoadReadout.isInFormBand(-9.4))
    #expect(!TrainingLoadReadout.isInFormBand(-24))
    #expect(!TrainingLoadReadout.isInFormBand(12))
}

@Test func aHeartRateOnlyStreamIsNotTakenForTheFullRecording() throws {
    let heartRateOnly = #"{"available":true,"path":[],"samples":[],"stats":{"totalDistance":null,"avgSpeed":null,"totalAscent":null}}"#
    let withRoute = #"{"available":true,"path":[[48.9,2.25],[48.91,2.26]],"samples":[],"stats":null}"#
    let withDistance = #"{"available":true,"path":null,"samples":[],"stats":{"totalDistance":1200,"avgSpeed":1.1,"totalAscent":null}}"#
    let decode = { (json: String) in try JSONDecoder().decode(V1ActivityStreamPayload.self, from: Data(json.utf8)) }
    #expect(try !decode(heartRateOnly).isComplete)
    #expect(try decode(withRoute).isComplete)
    #expect(try decode(withDistance).isComplete)
}
