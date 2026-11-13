import Foundation
import Testing
@testable import Sharpit

// Invented figures only: no real report is ever committed (SHARPIT ADR-128).

private func day(_ text: String) -> Date {
    APIDate.instant("\(text)T08:00:00.000Z")!
}

private func result(_ key: String, _ value: Double, low: Double? = nil, high: Double? = nil) -> V1BloodTest.Result {
    V1BloodTest.Result(markerKey: key, value: value, unit: BloodMarkerCatalog.marker(key)?.unit ?? "", refLow: low, refHigh: high)
}

private let older = V1BloodTest(id: "t1", sampledAt: day("2024-03-10"), results: [
    result("ferritin", 40, low: 30, high: 400),
    result("ast", 31, high: 50),
])
private let newer = V1BloodTest(id: "t2", sampledAt: day("2026-05-12"), results: [
    result("ferritin", 25, low: 30, high: 400),
    result("tsh", 1.4, low: 0.4, high: 4),
    result("ast", 28, high: 50),
])

// MARK: - Wire

@Test func aStoredTestDecodesFromTheServersShape() throws {
    let json = """
    { "bloodTests": [ { "id": "t2", "sampledAt": "2026-05-12T08:00:00.000Z",
      "results": [ { "markerKey": "ferritin", "value": 25, "unit": "µg/L", "refLow": 30, "refHigh": 400, "status": "low" },
                   { "markerKey": "cholesterol_total", "value": 1.7, "unit": "g/L", "refLow": null, "refHigh": null, "status": "no_reference" } ] } ] }
    """
    struct Body: Decodable { let bloodTests: [V1BloodTest] }
    let test = try #require(try JSONDecoder().decode(Body.self, from: Data(json.utf8)).bloodTests.first)

    #expect(test.sampledAt == day("2026-05-12"))
    #expect(test.results.map(\.status) == [.low, .noReference])
    #expect(test.outOfRangeCount == 1)
}

// MARK: - History

@Test func aMarkersHistoryIsOldestFirstAndSkipsTestsThatDidNotMeasureIt() {
    let tsh = BloodMarkerHistory(markerKey: "tsh", tests: [newer, older])
    let ferritin = BloodMarkerHistory(markerKey: "ferritin", tests: [newer, older])

    #expect(tsh.points.map(\.testId) == ["t2"])
    #expect(tsh.lastChange == nil)
    #expect(ferritin.points.map(\.value) == [40, 25])
    #expect(ferritin.lastChange == -15)
    #expect(ferritin.latest?.status == .low)
}

@Test func onlyMarkersMeasuredTwiceAreFollowedInCatalogOrder() {
    #expect(BloodMarkerHistory.followed(in: [newer, older]).map(\.markerKey) == ["ferritin", "ast"])
    #expect(BloodMarkerHistory.followed(in: [newer]).isEmpty)
}

// MARK: - Readout

@Test func aResultIsWordedAgainstTheLabsInterval() {
    #expect(BloodMarkerReadout.reference(low: 4.1, high: 10.8) == "4,1 – 10,8")
    #expect(BloodMarkerReadout.reference(low: nil, high: 1.5) == "< 1,5")
    #expect(BloodMarkerReadout.reference(low: 0.4, high: nil) == "> 0,4")
    #expect(BloodMarkerReadout.caption(status: .low, low: 30, high: 400) == "Bas · 30 – 400")
    #expect(BloodMarkerReadout.caption(status: .noReference, low: nil, high: nil) == "Sans intervalle")
    #expect(BloodMarkerReadout.delta(-15) == "−15")
    #expect(BloodMarkerReadout.delta(0.12) == "+0,12")
}

// MARK: - Store

private actor StubBloodTestServer: BloodTestServing {
    var tests: [V1BloodTest]
    let deleteFailure: SharpitAPIError?
    private(set) var deleted: [String] = []

    init(tests: [V1BloodTest], deleteFailure: SharpitAPIError? = nil) {
        self.tests = tests
        self.deleteFailure = deleteFailure
    }

    func bloodTests(token: String) async throws -> [V1BloodTest] { tests }

    func deleteBloodTest(id: String, token: String) async throws {
        if let deleteFailure { throw deleteFailure }
        deleted.append(id)
    }
}

@MainActor
@Test func theStoreReadsTheHistoryAndDeletesATest() async {
    let server = StubBloodTestServer(tests: [newer, older])
    let store = BloodTestsStore(client: server, tokenProvider: { "token" })

    await store.load()
    #expect(store.phase == .loaded)
    #expect(store.followedMarkers.count == 2)

    await store.delete("t1")
    #expect(store.tests.map(\.id) == ["t2"])
    #expect(await server.deleted == ["t1"])
}

@MainActor
@Test func aRefusedDeleteBringsTheTestBack() async {
    let store = BloodTestsStore(client: StubBloodTestServer(tests: [newer, older], deleteFailure: .badRequest), tokenProvider: { "token" })
    await store.load()

    await store.delete("t1")

    #expect(store.tests.map(\.id) == ["t2", "t1"])
}
