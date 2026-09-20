import Foundation
import Testing
@testable import Sharpit

// MARK: - Soreness scale

/// The athlete picks 1–5; the recovery extractors read a frozen 0–10 domain scale.
@Test func sorenessMapsOntoTheDomainScale() {
    #expect(WellnessSoreness.domain(fromUI: .one) == 0)
    #expect(WellnessSoreness.domain(fromUI: .three) == 5)
    #expect(WellnessSoreness.domain(fromUI: .five) == 10)
}

@Test func sorenessSnapsBackOntoTheTiles() {
    #expect(WellnessSoreness.ui(fromDomain: 0) == .one)
    #expect(WellnessSoreness.ui(fromDomain: 5) == .three)
    #expect(WellnessSoreness.ui(fromDomain: 10) == .five)
}

/// A row written by another client can carry anything; the picker must still open.
@Test func anOutOfRangeSorenessIsClamped() {
    #expect(WellnessSoreness.ui(fromDomain: -4) == .one)
    #expect(WellnessSoreness.ui(fromDomain: 99) == .five)
}

@Test func everyDimensionNamesItsFiveTiles() {
    for dimension in WellnessDimension.allCases {
        let labels = WellnessScore.allCases.map { dimension.label(for: $0) }
        let blanks = labels.filter(\.isEmpty)
        #expect(labels.count == 5)
        #expect(blanks.isEmpty)
    }
}

// MARK: - Store

private actor StubWellnessClient: WellnessServing {
    private let checkin: V1WellnessCheckin
    private let failsSubmit: Bool
    private(set) var submitted: [V1WellnessEntry] = []

    init(checkin: V1WellnessCheckin = V1WellnessCheckin(completed: false, entry: nil), failsSubmit: Bool = false) {
        self.checkin = checkin
        self.failsSubmit = failsSubmit
    }

    func wellnessCheckin(trainingDayId _: String, token _: String) async throws -> V1WellnessCheckin {
        checkin
    }

    func submitWellnessCheckin(
        _ entry: V1WellnessEntry,
        trainingDayId _: String,
        token _: String
    ) async throws {
        if failsSubmit { throw SharpitAPIError.server }
        submitted.append(entry)
    }

    func recorded() -> [V1WellnessEntry] { submitted }
}

@MainActor
@Test func theCheckInCannotBeSentHalfAnswered() async {
    let store = MorningWellnessStore(
        client: StubWellnessClient(),
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20"
    )
    await store.load()

    store.pick(.four, for: .mood)
    #expect(!store.canSubmit)

    store.pick(.three, for: .energy)
    store.pick(.two, for: .soreness)
    store.pick(.one, for: .stress)
    #expect(store.canSubmit)
}

/// A scale must be answered before the flow moves on; the note may be skipped.
@MainActor
@Test func aScaleBlocksTheNextStepButTheNoteDoesNot() async {
    let store = MorningWellnessStore(
        client: StubWellnessClient(),
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20"
    )
    await store.load()

    #expect(!store.canGoForward)
    store.pick(.four, for: .mood)
    #expect(store.canGoForward)

    store.step = MorningWellnessStore.noteStep
    #expect(store.isOnNoteStep)
    #expect(store.canGoForward)
}

@MainActor
@Test func submittingSendsTheDomainSorenessAndReturnsTheMoodLabel() async {
    let client = StubWellnessClient()
    let store = MorningWellnessStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20"
    )
    await store.load()

    store.pick(.four, for: .mood)
    store.pick(.five, for: .energy)
    store.pick(.five, for: .soreness)
    store.pick(.two, for: .stress)
    let label = await store.submit()

    #expect(label == "Bien")
    let sent = await client.recorded()
    #expect(sent.count == 1)
    #expect(sent.first?.mood == 4)
    #expect(sent.first?.perceivedSoreness == 10)
    #expect(sent.first?.notes == nil)
    #expect(store.alreadyCompleted)
}

@MainActor
@Test func aBlankNoteTravelsAsNothing() async {
    let client = StubWellnessClient()
    let store = MorningWellnessStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20"
    )
    await store.load()
    for dimension in WellnessDimension.allCases {
        store.pick(.three, for: dimension)
    }
    store.notes = "   \n  "

    _ = await store.submit()

    let sent = await client.recorded()
    #expect(sent.first?.notes == nil)
}

/// Reopening an answered morning must show what was answered, not a blank form.
@MainActor
@Test func anAnsweredMorningHydratesItsPicks() async {
    let entry = V1WellnessEntry(
        mood: 5,
        energyLevel: 2,
        perceivedSoreness: 10,
        stressLevel: 3,
        notes: "nuit hachée"
    )
    let store = MorningWellnessStore(
        client: StubWellnessClient(checkin: V1WellnessCheckin(completed: true, entry: entry)),
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20"
    )

    await store.load()

    #expect(store.alreadyCompleted)
    #expect(store.picks[.mood] == .five)
    #expect(store.picks[.energy] == .two)
    #expect(store.picks[.soreness] == .five)
    #expect(store.notes == "nuit hachée")
}

@MainActor
@Test func aRefusedSubmitReportsAndKeepsThePicks() async {
    let store = MorningWellnessStore(
        client: StubWellnessClient(failsSubmit: true),
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20"
    )
    await store.load()
    for dimension in WellnessDimension.allCases {
        store.pick(.three, for: dimension)
    }

    let label = await store.submit()

    #expect(label == nil)
    #expect(store.phase == .failed("Ton ressenti n'a pas pu être enregistré."))
    #expect(store.picks[.mood] == .three)
}
