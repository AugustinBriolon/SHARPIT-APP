import Foundation
import Testing
@testable import Sharpit

private func prefs(_ json: String) throws -> JournalPrefs {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    guard case .object(let raw) = value else {
        fatalError("fixture is not an object")
    }
    return JournalPrefs(raw: raw)
}

// MARK: - Preferences round-trip

/// The server rebuilds the enable map from defaults for every key a payload omits, so
/// a save from the phone that dropped the web's automatic items would turn them off.
@Test func savingOneTrackableKeepsTheOnesTheAppDoesNotRender() throws {
    var stored = try prefs("""
    { "version": 2,
      "enabled": { "steps_10k": true, "diet_keto": true, "alcohol": false },
      "thresholds": { "steps": 12000 } }
    """)

    stored.setEnabled("alcohol", true)

    #expect(stored.isEnabled("steps_10k"))
    #expect(stored.isEnabled("diet_keto"))
    #expect(stored.isEnabled("alcohol"))
    #expect(stored.raw["thresholds"]?["steps"] == .number(12000))
}

@Test func customItemsSurviveAWrite() throws {
    var stored = try prefs("""
    { "version": 2, "enabled": {},
      "customItems": [{ "id": "custom_abc123", "label": "Kiné", "enabled": true }] }
    """)

    #expect(stored.customItems == [JournalCustomItem(id: "custom_abc123", label: "Kiné", enabled: true)])

    stored.setCustomItems(stored.customItems + [
        JournalCustomItem(id: "custom_def456", label: "Sieste longue", enabled: false)
    ])

    #expect(stored.customItems.count == 2)
    #expect(stored.customItems.last?.label == "Sieste longue")
    #expect(stored.customItems.last?.enabled == false)
}

/// The cap counts what the web counts, including items this app never lists.
@Test func theFreeCapCountsEveryEnabledTrackable() throws {
    let stored = try prefs("""
    { "version": 2,
      "enabled": { "steps_10k": true, "nap": true, "alcohol": true, "fever": false },
      "customItems": [{ "id": "custom_abc123", "label": "Kiné", "enabled": true }] }
    """)

    #expect(stored.enabledCount == 4)
    #expect(stored.canEnableAnother(isPro: false))
}

@Test func aFullFreePlanCannotEnableAnother() throws {
    let enabled = (1...10).map { "\"item_\($0)\": true" }.joined(separator: ", ")
    let stored = try prefs("{ \"version\": 2, \"enabled\": { \(enabled) } }")

    #expect(stored.enabledCount == JournalPrefs.freeEnabledLimit)
    #expect(!stored.canEnableAnother(isPro: false))
    #expect(stored.canEnableAnother(isPro: true))
}

@Test func aCustomIdMatchesWhatTheServerAccepts() {
    let id = JournalPrefs.makeCustomId()
    #expect(id.wholeMatch(of: /custom_[a-zA-Z0-9_-]{4,64}/) != nil)
}

// MARK: - Day entry

@Test func theCycleFollowsTheWebsOrder() {
    #expect(JournalFactorState.unset.next == .yes)
    #expect(JournalFactorState.yes.next == .no)
    #expect(JournalFactorState.no.next == .unset)
}

/// A state the app does not model must not cost the whole day.
@Test func anUnknownFactorStateIsDroppedNotFatal() throws {
    let json = """
    { "entry": { "trainingDayId": "2026-09-20",
      "factors": { "alcohol": "yes", "sauna": "maybe" },
      "moodLabel": "Bien", "hydrationMl": 1500, "caffeineMg": 80 } }
    """
    let entry = try JSONDecoder().decode(V1DayJournalEnvelope.self, from: Data(json.utf8)).entry

    #expect(entry?.state(of: "alcohol") == .yes)
    #expect(entry?.state(of: "sauna") == .unset)
    #expect(entry?.moodLabel == "Bien")
    #expect(entry?.hydrationMl == 1500)
}

@Test func aDayWithNothingRecordedReadsAsEmpty() throws {
    let json = #"{ "entry": { "trainingDayId": "2026-09-20", "factors": {} } }"#
    let entry = try JSONDecoder().decode(V1DayJournalEnvelope.self, from: Data(json.utf8)).entry

    #expect(entry?.state(of: "alcohol") == .unset)
    #expect(entry?.moodLabel == nil)
    #expect(entry?.caffeineMg == 0)
}

/// The journal stores the mood's label, not a code, so both sides must spell it alike.
@Test func moodsCarryTheWebsVocabulary() {
    let labels = WellnessScore.allCases.map { WellnessDimension.mood.label(for: $0) }
    #expect(labels == ["Très bas", "Bas", "Correct", "Bien", "Top"])
}

// MARK: - Store

private actor StubJournalClient: JournalServing {
    private var entry: V1DayJournalEntry
    private var storedPrefs: JournalPrefs
    private let isPro: Bool
    private(set) var entrySaves = 0

    init(
        entry: V1DayJournalEntry = V1DayJournalEntry(trainingDayId: "2026-09-20"),
        prefs: JournalPrefs = .empty,
        isPro: Bool = false
    ) {
        self.entry = entry
        storedPrefs = prefs
        self.isPro = isPro
    }

    func dayJournal(trainingDayId _: String, token _: String) async throws -> V1DayJournalEntry {
        entry
    }

    func saveDayJournal(
        _ entry: V1DayJournalEntry,
        token _: String
    ) async throws -> V1DayJournalEntry {
        entrySaves += 1
        self.entry = entry
        return entry
    }

    func journalPrefs(token _: String) async throws -> (prefs: JournalPrefs, isPro: Bool) {
        (storedPrefs, isPro)
    }

    func saveJournalPrefs(
        _ prefs: JournalPrefs,
        token _: String
    ) async throws -> (prefs: JournalPrefs, isPro: Bool) {
        storedPrefs = prefs
        return (prefs, isPro)
    }

    func saveCount() -> Int { entrySaves }
}

@MainActor
@Test func onlyEnabledTrackablesAreAsked() async throws {
    let client = StubJournalClient(
        prefs: try prefs(#"{ "version": 2, "enabled": { "alcohol": true, "sauna": true } }"#)
    )
    let store = JournalStore(client: client, tokenProvider: { "token" })

    await store.load()

    #expect(store.visibleTrackables.map(\.id) == ["alcohol", "sauna"])
    #expect(!store.hasNothingToShow)
}

/// Cycling a signal through its three states must cost one request, not three.
@MainActor
@Test func rapidTapsCollapseIntoOneWrite() async throws {
    let client = StubJournalClient()
    let store = JournalStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20",
        saveDelay: .milliseconds(30)
    )
    await store.load()

    store.cycle(factorId: "alcohol")
    store.cycle(factorId: "alcohol")
    store.cycle(factorId: "alcohol")
    #expect(store.entry.state(of: "alcohol") == .unset)

    await store.flushPendingSave()

    #expect(await client.saveCount() == 1)
}

/// Leaving the screen a moment after a tap must not lose it.
@MainActor
@Test func aPendingWriteIsFlushedOnLeaving() async {
    let client = StubJournalClient()
    let store = JournalStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20",
        saveDelay: .seconds(60)
    )
    await store.load()

    store.applyMoodLabel("Bien")
    await store.flushPendingSave()

    #expect(await client.saveCount() == 1)
    #expect(store.entry.moodLabel == "Bien")
}

@MainActor
@Test func caffeineAndHydrationStepTheWaySheWebDoesAndStopAtZero() async {
    let store = JournalStore(
        client: StubJournalClient(),
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20",
        saveDelay: .seconds(60)
    )
    await store.load()

    store.adjustCaffeine(by: 40)
    store.adjustCaffeine(by: 40)
    store.adjustHydration(by: 250)
    store.adjustHydration(by: -250)
    store.adjustHydration(by: -250)

    #expect(store.entry.caffeineMg == 80)
    #expect(store.entry.hydrationMl == 0)
}

@MainActor
@Test func aFreePlanCannotAddACustomTrackable() async {
    let client = StubJournalClient(isPro: false)
    let store = JournalStore(client: client, tokenProvider: { "token" })
    await store.load()

    await store.addCustomItem(label: "Kiné")

    #expect(store.prefs.customItems.isEmpty)
}

@MainActor
@Test func aProPlanAddsACustomTrackableEnabled() async {
    let client = StubJournalClient(isPro: true)
    let store = JournalStore(client: client, tokenProvider: { "token" })
    await store.load()

    await store.addCustomItem(label: "  Kiné  ")

    #expect(store.prefs.customItems.count == 1)
    #expect(store.prefs.customItems.first?.label == "Kiné")
    #expect(store.visibleCustomItems.count == 1)
}

@MainActor
@Test func aFullFreePlanRefusesToEnableAnother() async throws {
    let enabled = (1...10).map { "\"item_\($0)\": true" }.joined(separator: ", ")
    let client = StubJournalClient(
        prefs: try prefs("{ \"version\": 2, \"enabled\": { \(enabled) } }")
    )
    let store = JournalStore(client: client, tokenProvider: { "token" })
    await store.load()

    await store.setTrackableEnabled("alcohol", true)

    #expect(!store.prefs.isEnabled("alcohol"))
}
