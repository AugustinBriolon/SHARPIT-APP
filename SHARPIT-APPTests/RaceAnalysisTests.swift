import Foundation
import Testing
@testable import Sharpit

// MARK: - Stub for the list read

private nonisolated final class RaceListStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data("[]".utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func detailJSON(id: String, title: String) -> Data {
    Data(#"{"id":"\#(id)","type":"TRIATHLON","date":"2026-10-11T08:19:42.000Z","title":"\#(title)","duration":20403}"#.utf8)
}

private let analysisJSON = """
{"target":{"label":"Sub 5h30","seconds":19800},"total":{"seconds":20403,"deltaSec":603},
 "legs":[
  {"kind":"swim","label":"Natation","durationSec":1522,"distanceM":1900,"sourceActivityId":"swim-1","avgHr":142,
   "hrZonesSec":[100,400,600,300,122],"pacing":{"unit":"sec_per_100m","firstHalf":112,"secondHalf":118,"changePct":5.4}},
  {"kind":"transition","label":"T1","durationSec":581,"sourceActivityId":"t1","hrZonesSec":null,"pacing":null},
  {"kind":"bike","label":"Vélo","durationSec":11516,"distanceM":90000,"avgHr":135,
   "hrZonesSec":[0,0,0,0,0],"pacing":{"unit":"kmh","firstHalf":28.4,"secondHalf":28.1,"changePct":1.1}},
  {"kind":"transition","label":"T2","durationSec":358},
  {"kind":"run","label":"Course à pied","durationSec":6425,"distanceM":21100,"sourceActivityId":"run-1",
   "pacing":{"unit":"sec_per_km","firstHalf":290,"secondHalf":318,"changePct":"oops"}}
 ],
 "runHrDriftPct":7.25,"load":{"tss":312.4,"recoveryHours":36}}
"""

@Suite(.serialized)
struct RaceAnalysisTests {

    // MARK: Detail cache

    @Test func aDetailDisagreeingWithTheListIsStale() throws {
        let old = try JSONDecoder().decode(V1ActivityDetail.self, from: detailJSON(id: "a1", title: "Half IronMan Versailles"))
        let renamed = V1ActivityListItem(id: "a1", type: .triathlon, date: old.date, title: "Versailles Multisport", duration: 20403)
        let same = V1ActivityListItem(id: "a1", type: .triathlon, date: old.date, title: "Half IronMan Versailles", duration: 20403)
        #expect(!ActivityCachePolicy.detail(old, agreesWith: renamed))
        #expect(ActivityCachePolicy.detail(old, agreesWith: same))
    }

    @Test func aListReadDropsTheStaleDiskDetailOnly() async throws {
        let disk = ActivityDiskCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        disk.write(detailJSON(id: "a1", title: "Versailles Multisport"), .detail, id: "a1")
        disk.write(detailJSON(id: "a2", title: "Sortie longue"), .detail, id: "a2")
        RaceListStubURLProtocol.responseData = Data("""
        [{"id":"a1","type":"TRIATHLON","date":"2026-10-11T08:19:42.000Z","title":"Half IronMan Versailles","duration":20403},
         {"id":"a2","type":"TRIATHLON","date":"2026-10-11T08:19:42.000Z","title":"Sortie longue","duration":20403}]
        """.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RaceListStubURLProtocol.self]
        let client = ActivityClient(
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://sharpit.example")!,
            disk: disk
        )

        _ = try await client.activities(forceRefresh: true, token: "t")

        #expect(disk.read(.detail, id: "a1") == nil)
        #expect(disk.read(.detail, id: "a2") != nil)
    }

    @Test func aTriathlonHasNoKilometreSplits() {
        #expect(!V1ActivityType.triathlon.supportsSplits)
        #expect(V1ActivityType.run.supportsSplits)
    }

    // MARK: Decoding

    @Test func raceAnalysisDecodesLenientlyOnTheDetail() throws {
        let json = #"{"id":"a1","type":"TRIATHLON","date":"2026-10-11T08:19:42Z","raceAnalysis":\#(analysisJSON)}"#
        let detail = try JSONDecoder().decode(V1ActivityDetail.self, from: Data(json.utf8))
        let analysis = try #require(detail.raceAnalysis)
        #expect(analysis.legs.count == 5)
        #expect(analysis.legs[4].pacing == nil)
        #expect(analysis.legs[0].sourceActivityId == "swim-1")

        let broken = #"{"id":"a1","type":"TRIATHLON","date":"2026-10-11T08:19:42Z","raceAnalysis":{"legs":[]}}"#
        #expect(try JSONDecoder().decode(V1ActivityDetail.self, from: Data(broken.utf8)).raceAnalysis == nil)
        let older = #"{"id":"a1","type":"RUN","date":"2026-10-11T08:19:42Z"}"#
        #expect(try JSONDecoder().decode(V1ActivityDetail.self, from: Data(older.utf8)).raceAnalysis == nil)
    }

    // MARK: Readout

    private func analysis() throws -> V1RaceAnalysis {
        try JSONDecoder().decode(V1RaceAnalysis.self, from: Data(analysisJSON.utf8))
    }

    @Test func theObjectiveBlockReadsTheTotalAndEachLeg() throws {
        let analysis = try analysis()
        #expect(RaceAnalysisReadout.objectiveTitle(analysis) == "Par rapport à l'objectif")
        #expect(RaceAnalysisReadout.totalLine(analysis) == "5:40:03 · +10:03 vs objectif Sub 5h30")
        let rows = RaceAnalysisReadout.legRows(analysis)
        #expect(rows.map(\.segment.label) == ["Natation", "T1", "Vélo", "T2", "Course"])
        #expect(rows.map(\.sourceActivityId) == ["swim-1", "t1", nil, nil, "run-1"])
        #expect(rows[0].detail == "1,9 km · FC moy 142")
        #expect(rows[3].detail == nil)
    }

    @Test func zonesAreSharesOfLegsWithHeartRate() throws {
        let rows = RaceAnalysisReadout.zoneRows(try analysis())
        #expect(rows.map(\.label) == ["Natation"])
        let shares = try #require(rows.first?.shares)
        let total: Double = shares.reduce(0, +)
        #expect(abs(total - 1) < 0.000_001)
        #expect(rows.first?.averageLine == "FC moy 142")
    }

    @Test func effortReadsHalvesAndDrift() throws {
        let rows = RaceAnalysisReadout.effortRows(try analysis())
        #expect(rows.map(\.label) == ["Natation", "Vélo", "Dérive cardiaque"])
        #expect(rows[0].value == "1:52 → 1:58")
        #expect(rows[0].note == "/100 m · Ralenti de 5,4 % en 2e moitié")
        #expect(rows[1].value == "28,4 → 28,1")
        #expect(rows[1].note == "km/h · Allure tenue")
        #expect(rows[2].value == "+7,2 %" || rows[2].value == "+7,3 %")
        #expect(RaceAnalysisReadout.changeNote(-3) == "Accéléré de 3 % en 2e moitié")
    }

    @Test func loadIsNamedForTheReading() throws {
        let analysis = try analysis()
        #expect(RaceAnalysisReadout.loadRows(analysis, isExpertReading: false).map(\.label) == ["Charge", "Récupération"])
        #expect(RaceAnalysisReadout.loadRows(analysis, isExpertReading: true).first?.label == "TSS")
        #expect(RaceAnalysisReadout.loadRows(analysis, isExpertReading: false).map(\.value) == ["312", "≈ 36 h"])
    }

    @Test func withoutATargetTheBlockIsTheChain() throws {
        var analysis = try analysis()
        analysis.target = nil
        analysis.total.deltaSec = nil
        #expect(RaceAnalysisReadout.objectiveTitle(analysis) == "Enchaînement")
        #expect(RaceAnalysisReadout.totalLine(analysis) == "5:40:03")
    }
}

struct ActivitySplitFigureTests {
    private func split(paceSeconds: Double) -> ActivitySplit {
        ActivitySplit(id: 0, distanceLabel: "5 km", paceSeconds: paceSeconds, variation: 0, heartRate: nil, elevationGain: 0, progress: 1)
    }

    @Test func aRideSplitReadsInKilometresPerHour() {
        #expect(split(paceSeconds: 120).figure(segmentDistance: 5_000) == "30,0 km/h")
    }

    @Test func aRunSplitKeepsItsPacePerKilometre() {
        #expect(split(paceSeconds: 300).figure(segmentDistance: 1_000) == ActivityFormat.pace(300))
    }
}
