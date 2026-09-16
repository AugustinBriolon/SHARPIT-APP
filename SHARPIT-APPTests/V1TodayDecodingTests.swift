import Foundation
import Testing
@testable import Sharpit

@Test func decodesFullHero() throws {
    let decoded = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    #expect(decoded.apiVersion == 1)
    #expect(decoded.empty == nil)
    #expect(decoded.verdict.posture == .steady)
    #expect(decoded.sessions.first?.kind == .planned)
    #expect(decoded.signals.count == 2)
    #expect(decoded.verdict.statusLabel == "FEU VERT")
    #expect(decoded.verdict.packTier == .partial)
    #expect(decoded.sessions.first?.sport == "Course")
    #expect(decoded.sessions.first?.priority == true)
}

@Test func decodesEmptyNoContent() throws {
    let decoded = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("empty.json"))
    #expect(decoded.empty?.code == .noContent)
    #expect(decoded.empty?.webURL.hasPrefix("https://") == true)
}

@Test func decodesSparseWeatherAndSessions() throws {
    let decoded = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("sparse.json"))
    #expect(decoded.weather == nil)
    #expect(decoded.sessions.isEmpty)
}

@Test func emptyPayloadWinsOverVerdict() throws {
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("empty.json"))
    let state = TodayModel.state(from: response)
    guard case .empty(let empty) = state else {
        Issue.record("expected empty")
        return
    }
    #expect(empty.code == .noContent)
}

@Test func fullPayloadIsLoaded() throws {
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    let state = TodayModel.state(from: response)
    guard case .loaded(let loaded) = state else {
        Issue.record("expected loaded")
        return
    }
    #expect(loaded.weather != nil)
}

@Test func trainingDayDisplayNameUsesFrenchMonth() {
    let label = TrainingDayId.displayName("2026-09-15")
    #expect(label.contains("15"))
    #expect(label.localizedCaseInsensitiveContains("sept"))
    #expect(TrainingDayId.displayName("not-a-date") == "Résumé")
}

func fixtureData(_ name: String) throws -> Data {
    let url = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/\(name)")
    return try Data(contentsOf: url)
}
