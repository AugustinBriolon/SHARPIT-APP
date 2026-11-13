import Foundation
import Testing
@testable import Sharpit

// Every figure below is invented: no real report is ever committed (SHARPIT ADR-128).

private func line(_ text: String, y: Double, x: Double = 33, height: Double = 9, page: Int = 0, confidence: Double = 1) -> ReportTextLine {
    ReportTextLine(text: text, page: page, midY: y, minX: x, height: height, confidence: confidence)
}

private func result(_ key: String, in lines: [ReportTextLine]) -> ParsedBloodResult? {
    BloodReportParser.parse(lines).results.first { $0.markerKey == key }
}

// MARK: - Parser

@Test func aResultOnOneLineIsReadWithItsBoundsAndNotThePreviousValue() {
    let hemoglobin = result("hemoglobin", in: [line("Hémoglobine** 15,2 g/dL (13,4−16,7) 14,9", y: 467)])

    #expect(hemoglobin == ParsedBloodResult(markerKey: "hemoglobin", value: 15.2, unit: "g/dL", refLow: 13.4, refHigh: 16.7, confidence: 1))
}

/// A PDF lists such a value before its label, after the previous marker's method note: only the
/// position ties it to the right marker.
@Test func aValuePrintedBesideItsLabelIsTiedByPositionNotByReadingOrder() {
    let lines = [
        line("Phosphatases alcalines**", y: 584.4),
        line("(Colorimétrie cinétique standardisée IFCC)", y: 576.1, height: 5.8),
        line("71 U/L (40−129)", y: 584.6, x: 325),
        line("16−03−2023", y: 554, x: 522, height: 6.7),
        line("27 U/L (< 50) 31", y: 541.8, x: 325),
        line("ASAT (Transaminases TGO)**", y: 541.5),
        line("(IFCC, avec phosphate de pyridoxal)", y: 533.2, height: 5.8),
    ]
    let report = BloodReportParser.parse(lines)

    #expect(report.results.map(\.markerKey) == ["alkaline_phosphatase", "ast"])
    #expect(report.results.map(\.value) == [71, 27])
    #expect(report.results[1].refLow == nil)
    #expect(report.results[1].refHigh == 50)
}

@Test func theMarkersOwnUnitPicksTheValueAmongSeveral() {
    let lines = [
        line("Polynucléaires neutrophiles** 52,0 % 2,90 G/L (1,80−6,80) 2,50", y: 380),
        line("Créatinine** 9,8 mg/L (6,7−11,7) 10,2", y: 187),
        line("(Colorimétrique enzymatique ) 87 µmol/L (59−103) 90", y: 176.7, height: 8.1),
    ]

    #expect(result("neutrophils", in: lines)?.value == 2.9)
    #expect(result("creatinine", in: lines)?.value == 9.8)
    #expect(BloodReportParser.parse(lines).results.count == 2)
}

@Test func theLongestLabelWinsAndAnUnknownUnitIsNoResult() {
    let lines = [
        line("Cholestérol total** 1,82 g/L (< 1,90)", y: 227),
        line("Cholestérol HDL** 0,61 g/L (0,40−0,80)", y: 200),
        line("Cholestérol 1,70 g/L", y: 180, page: 1),
        line("Hémoglobine glyquée 5,2 %", y: 160),
        line("Ferritine 95 Hg/L (30−400)", y: 140),
    ]
    let report = BloodReportParser.parse(lines)

    #expect(report.results.map(\.markerKey) == ["cholesterol_total", "cholesterol_hdl"])
    #expect(report.results[0].value == 1.82)
}

/// A recogniser's boxes for one printed line differ in height and by a few thousandths in y.
@Test func piecesOfOneRecognisedLineAreJoinedDespiteUnevenBoxes() {
    let lines = [
        line("19", y: 0.544, x: 0.926, height: 0.009, confidence: 0.5),
        line("(<60)", y: 0.543, x: 0.692, height: 0.016, confidence: 0.5),
        line("15 U/L", y: 0.542, x: 0.542, height: 0.015, confidence: 0.3),
        line("GGT (Gamma Glutamyl Transpeptidase) **", y: 0.540, x: 0.053, height: 0.019, confidence: 0.5),
        line("(Test colorimétrique enzymatique)", y: 0.531, x: 0.055, height: 0.010),
        line("(Potentiométrie indirecte)", y: 0.700, x: 0.055, height: 0.010),
        line("Sodium sérique **", y: 0.710, x: 0.055, height: 0.012),
    ]

    #expect(result("ggt", in: lines) == ParsedBloodResult(markerKey: "ggt", value: 15, unit: "U/L", refLow: nil, refHigh: 60, confidence: 0.3))
}

@Test func theSamplingDateIsReadAndIdentityLinesYieldNothing() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
    let lines = [
        line("Nom de naissance : DUPONT", y: 680),
        line("Date de naissance : 01−02−1990", y: 661),
        line("Prescrit par DR MARTIN - RPPS : 10000000000", y: 616),
        line("Prélevé le 12−05−2026 08:30 au laboratoire", y: 591),
    ]
    let report = BloodReportParser.parse(lines, calendar: calendar)

    #expect(report.results.isEmpty)
    #expect(report.sampledAt == calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 8, minute: 30)))
}

// MARK: - Draft

@Test func aDraftCannotBeSavedWithAValueNoAdultShows() {
    let report = ParsedBloodReport(sampledAt: nil, results: [
        ParsedBloodResult(markerKey: "potassium", value: 43, unit: "mmol/L", refLow: 3.5, refHigh: 5.1, confidence: 0.5),
    ])
    var draft = BloodTestDraft(report)

    #expect(draft.isRecognised)
    #expect(!draft.canSave)

    draft.rows[0].value = 4.3
    #expect(draft.canSave)
    #expect(draft.rows[0].status == .inRange)
    #expect(draft.inputs == [BloodTestResultInput(markerKey: "potassium", value: 4.3, unit: "mmol/L", refLow: 3.5, refHigh: 5.1)])
}

@Test func aMarkerAddedByHandBlocksTheSaveUntilItHasAValue() throws {
    var draft = BloodTestDraft(ParsedBloodReport(sampledAt: nil, results: [
        ParsedBloodResult(markerKey: "tsh", value: 1.2, unit: "mUI/L", refLow: 0.4, refHigh: 4, confidence: 1),
    ]))
    let ferritin = try #require(draft.missingMarkers.first { $0.key == "ferritin" })

    draft.add(ferritin)
    draft.add(ferritin)

    #expect(draft.rows.map(\.markerKey) == ["tsh", "ferritin"])
    #expect(!draft.canSave)
    #expect(!draft.missingMarkers.contains { $0.key == "ferritin" })
}

@Test func aStatusReadsTheLabsBoundsOnly() {
    #expect(BloodMarkerStatus(value: 3.6, refLow: 4.1, refHigh: 10.8) == .low)
    #expect(BloodMarkerStatus(value: 2.2, refLow: nil, refHigh: 1.9) == .high)
    #expect(BloodMarkerStatus(value: 4.1, refLow: 4.1, refHigh: 10.8) == .inRange)
    #expect(BloodMarkerStatus(value: 1.6, refLow: nil, refHigh: nil) == .noReference)
}

// MARK: - Client and store

@Test func aRefusalIsToldFromAServerFailure() {
    #expect(throws: SharpitAPIError.unauthorized) { try BloodTestClient.check(status: 401) }
    #expect(throws: SharpitAPIError.badRequest) { try BloodTestClient.check(status: 400) }
    #expect(throws: SharpitAPIError.server) { try BloodTestClient.check(status: 503) }
    #expect(throws: Never.self) { try BloodTestClient.check(status: 201) }
}

private actor StubBloodTestClient: BloodTestWriting {
    private(set) var sent: [[BloodTestResultInput]] = []
    let failure: SharpitAPIError?

    init(failure: SharpitAPIError? = nil) { self.failure = failure }

    func createBloodTest(sampledAt: Date, results: [BloodTestResultInput], token: String) async throws {
        if let failure { throw failure }
        sent.append(results)
    }
}

private let confirmedReport = ParsedBloodReport(sampledAt: nil, results: [
    ParsedBloodResult(markerKey: "ferritin", value: 61, unit: "µg/L", refLow: 30, refHigh: 400, confidence: 1),
])

@MainActor
@Test func savingSendsTheConfirmedResultsAndDropsTheDraft() async {
    let client = StubBloodTestClient()
    let store = BloodTestImportStore(client: client, tokenProvider: { "token" })
    store.draft = BloodTestDraft(confirmedReport)

    await store.save()

    #expect(store.phase == .saved)
    #expect(store.draft == nil)
    #expect(await client.sent == [[BloodTestResultInput(markerKey: "ferritin", value: 61, unit: "µg/L", refLow: 30, refHigh: 400)]])
}

@MainActor
@Test func aRefusedSaveKeepsTheDraftAndSaysWhy() async {
    let store = BloodTestImportStore(client: StubBloodTestClient(failure: .badRequest), tokenProvider: { "token" })
    store.draft = BloodTestDraft(confirmedReport)

    await store.save()

    #expect(store.phase == .review)
    #expect(store.draft != nil)
    #expect(store.errorMessage != nil)
}
