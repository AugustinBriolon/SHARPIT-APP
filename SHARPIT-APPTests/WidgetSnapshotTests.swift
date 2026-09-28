import Foundation
import Testing
@testable import Sharpit

private func fold(day: String = "2026-09-28", sessions: [SessionCardModel]) -> TodayFold {
    TodayFold(
        trainingDayId: day,
        plate: InkPlateModel(
            statusLabel: "Feu vert",
            headline: "Séance clé possible",
            actionLine: "Tiens le seuil.",
            limitingCause: nil,
            confidencePct: 80,
            confidenceLabel: nil,
            packTier: .full,
            estimationGaps: [],
            posture: .push
        ),
        sessions: sessions,
        gauges: [],
        consistency: nil,
        weather: nil
    )
}

private func card(_ id: String, _ kind: V1TodaySessionKind, sport: String = "Course") -> SessionCardModel {
    SessionCardModel(
        id: id,
        kind: kind,
        title: "Seuil \(id)",
        subtitle: nil,
        metrics: [
            V1TodayMetric(label: "Durée", value: "55", unit: "min"),
            V1TodayMetric(label: "Charge", value: "62", unit: ""),
            V1TodayMetric(label: "Intensité", value: "Seuil", unit: ""),
        ],
        sport: sport,
        priority: false
    )
}

/// The widgets say what Résumé says: its verdict, its sessions, their first figures.
@Test func theWidgetsShowRésuméDay() {
    let snapshot = WidgetSnapshot(fold: fold(sessions: [card("a", .done, sport: "Vélo"), card("b", .planned)]))

    #expect(snapshot.verdict?.status == "Feu vert")
    #expect(snapshot.verdict?.posture == .push)
    #expect(snapshot.sessions.map(\.isDone) == [true, false])
    #expect(snapshot.sessions.first?.sport == .bike)
    #expect(snapshot.sessions.first?.figures == ["55 min", "62"])
    // The session still to do comes first; once all are done, the last one.
    #expect(snapshot.leadSession?.id == "b")
}

@Test func onceEverythingIsDoneTheLastSessionLeads() {
    let snapshot = WidgetSnapshot(fold: fold(sessions: [card("a", .done), card("b", .done)]))
    #expect(snapshot.leadSession?.id == "b")
}

/// Yesterday's snapshot is never shown as today's.
@Test func aSnapshotBelongsToItsDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let snapshot = WidgetSnapshot(fold: fold(sessions: []))
    let sameDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 23))!
    let nextDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 0, minute: 5))!

    #expect(snapshot.isFor(day: sameDay, calendar: calendar))
    #expect(!snapshot.isFor(day: nextDay, calendar: calendar))
}

@Test func theSnapshotRoundTripsThroughItsFileAndIsErased() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let snapshot = WidgetSnapshot(fold: fold(sessions: [card("a", .planned)]), writtenAt: Date(timeIntervalSince1970: 1_790_000_000))

    try WidgetSnapshotStore.write(snapshot, to: directory)
    #expect(WidgetSnapshotStore.read(from: directory) == snapshot)

    WidgetSnapshotStore.erase(in: directory)
    #expect(WidgetSnapshotStore.read(from: directory) == nil)
}
