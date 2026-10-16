import Foundation
import SwiftUI
import Testing
@testable import Sharpit

private func day(
    energyBank: V1TodayEnergyBank? = nil,
    stress: V1TodayStress? = nil,
    targetBand: V1TodayTargetBand? = nil
) throws -> V1TodayResponse {
    var response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    response.energyBank = energyBank
    response.stress = stress
    response.targetBand = targetBand
    return response
}

private let bank = V1TodayEnergyBank(algorithmVersion: "v1", value: 63.6, typicalBaseline: 71.2, asOfMinuteOfDay: 600, series: [])

@Test func santeDayStateMapsAllThreeReadings() throws {
    let state = try #require(SanteDayState(day(
        energyBank: bank,
        stress: V1TodayStress(value: 52, asOf: "2026-10-12T08:00:00Z"),
        targetBand: V1TodayTargetBand(algorithmVersion: "v1", low: 8.4, high: 12.6, status: "within")
    )))
    #expect(state.tiles == [
        .init(caption: "Énergie", value: "64", unit: "/100", note: "D'habitude 71"),
        .init(caption: "Stress", value: "52", unit: "/100", note: "Modéré"),
        .init(caption: "Effort visé", value: "8–13", unit: nil, note: "Atteint"),
    ])
}

@Test func santeDayStateIsNilWithoutReadings() throws {
    #expect(SanteDayState(try day()) == nil)
    // An Energy Bank without a value yet says nothing.
    let pending = V1TodayEnergyBank(algorithmVersion: "v1", value: nil, typicalBaseline: 70, asOfMinuteOfDay: 0, series: [])
    #expect(SanteDayState(try day(energyBank: pending)) == nil)
}

@Test func santeDayStateKeepsOnlyWhatIsThere() throws {
    let state = try #require(SanteDayState(day(stress: V1TodayStress(value: 80, asOf: "x"))))
    #expect(state.tiles.map(\.caption) == ["Stress"])
    #expect(state.tiles.first?.note == "Élevé")
}

@Test func santeDayStateWordsStressAndBandStatus() {
    #expect(SanteDayState.stressCaption(49) == "Calme")
    #expect(SanteDayState.stressCaption(75) == "Élevé")
    #expect(SanteDayState.statusLabel("below") == "Encore à faire")
    #expect(SanteDayState.statusLabel("above") == "Dépassé")
    #expect(SanteDayState.statusLabel(nil) == nil)
}

private struct StubDay: TodayServing {
    let response: V1TodayResponse
    func today(trainingDayId _: String, token _: String) async throws -> V1TodayResponse { response }
}

@MainActor
@Test func santeStoreLoadsTheDayFromToday() async throws {
    let store = SanteStore(todayClient: StubDay(response: try day(energyBank: bank)), tokenProvider: { "t" })
    #expect(store.dayState == nil)
    await store.loadDay()
    #expect(store.dayState?.tiles.first?.value == "64")
}

@Test func triathlonResolvesToTheCustomSymbol() {
    #expect(V1ActivityType.triathlon.symbolName == SharpitCustomSymbol.triathlon)
    #expect(SharpitCustomSymbol.accessibilityLabels[V1ActivityType.triathlon.symbolName] == "Triathlon")
    #expect(plannedSymbol("triathlon") == SharpitCustomSymbol.triathlon)
}

@Test func otherSportsStaySFSymbols() {
    for type in [V1ActivityType.run, .bike, .swim, .strength, .hike, .other] {
        #expect(SharpitCustomSymbol.accessibilityLabels[type.symbolName] == nil)
        #expect(UIImage(systemName: type.symbolName) != nil)
    }
    #expect(plannedSymbol("RUN") == "figure.run")
    #expect(plannedSymbol(nil) == V1ActivityType.other.symbolName)
}

@Test func triathlonSymbolShipsInTheBundle() {
    #expect(UIImage(named: SharpitCustomSymbol.triathlon) != nil)
}

private func plannedSymbol(_ type: String?) -> String {
    V1PlannedSessionItem(id: "p", date: .now, title: "Séance", type: type).symbolName
}
