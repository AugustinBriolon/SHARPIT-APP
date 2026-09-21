import Foundation
import Testing
@testable import Sharpit

// Session load is shown in both readings and only named differently (ADR 0006). These
// cover the naming and the surfaces that carry it, not the density itself.

/// Both readings show the number; only the word changes (ADR 0006).
@Test func sessionLoadIsNamedForTheReadingItIsShownIn() {
    #expect(ActivityFormat.trainingLoad(78.4, isExpertReading: false) == "charge 78")
    #expect(ActivityFormat.trainingLoad(78.4, isExpertReading: true) == "78 TSS")
}

@Test func aPlannedSessionStatesWhatItWillCost() {
    let session = V1PlannedSessionItem(
        id: "p1",
        date: Date(timeIntervalSince1970: 1_800_000_000),
        title: "Seuil",
        type: "bike",
        durationMin: 75,
        intensity: "seuil",
        load: 92
    )

    let essential = PlannedSessionPreview(session: session)
    let expert = PlannedSessionPreview(session: session, isExpertReading: true)

    #expect(essential.metrics.map(\.label) == ["Durée", "Intensité", "Charge"])
    #expect(essential.metrics.last?.value == "92")
    #expect(expert.metrics.map(\.label) == ["Durée", "Intensité", "TSS"])
}

/// A session with no load planned must not show an empty metric.
@Test func aPlannedSessionWithoutALoadShowsNone() {
    let session = V1PlannedSessionItem(
        id: "p2",
        date: Date(timeIntervalSince1970: 1_800_000_000),
        title: "Récup",
        type: "run",
        durationMin: 40
    )

    #expect(PlannedSessionPreview(session: session).metrics.map(\.label) == ["Durée"])
}
