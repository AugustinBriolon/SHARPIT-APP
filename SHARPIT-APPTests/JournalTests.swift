import Foundation
import SwiftData
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
    private let saveLatency: Duration
    private(set) var entrySaves = 0
    private let signals: V1JournalDaySignals?
    private(set) var signalReads = 0

    init(
        entry: V1DayJournalEntry = V1DayJournalEntry(trainingDayId: "2026-09-20"),
        prefs: JournalPrefs = .empty,
        isPro: Bool = false,
        saveLatency: Duration = .zero,
        signals: V1JournalDaySignals? = nil
    ) {
        self.entry = entry
        storedPrefs = prefs
        self.isPro = isPro
        self.saveLatency = saveLatency
        self.signals = signals
    }

    /// Nil `signals` stands for a route that failed, which is the case the journal has to
    /// survive.
    func journalDaySignals(
        trainingDayId _: String,
        token _: String
    ) async throws -> V1JournalDaySignals {
        signalReads += 1
        guard let signals else { throw SharpitAPIError.server }
        return signals
    }

    func signalReadCount() -> Int { signalReads }

    func dayJournal(trainingDayId _: String, token _: String) async throws -> V1DayJournalEntry {
        entry
    }

    func saveDayJournal(
        _ entry: V1DayJournalEntry,
        token _: String
    ) async throws -> V1DayJournalEntry {
        entrySaves += 1
        self.entry = entry
        try await Task.sleep(for: saveLatency)
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

/// The server echoes what it was sent. A tap made while that request is in flight must
/// survive the echo, on screen and in the next write.
@MainActor
@Test func aTapDuringASaveIsNotRevertedByTheEcho() async throws {
    let client = StubJournalClient(saveLatency: .milliseconds(200))
    let store = JournalStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20",
        saveDelay: .seconds(60)
    )
    await store.load()

    store.set(factorId: "alcohol", to: .yes)
    let firstSave = Task { await store.flushPendingSave() }
    try await Task.sleep(for: .milliseconds(50))
    store.set(factorId: "sauna", to: .yes)
    await firstSave.value

    #expect(store.entry.state(of: "sauna") == .yes)

    await store.flushPendingSave()
    let reloaded = try await client.dayJournal(trainingDayId: "2026-09-20", token: "token")
    #expect(reloaded.state(of: "alcohol") == .yes)
    #expect(reloaded.state(of: "sauna") == .yes)
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

// MARK: - Which window a signal belongs to

/// The seven ids are listed by hand rather than derived: this is the parity contract with
/// `../SHARPIT/src/lib/journal/day-context-factors.ts`, and it has to break if one moves.
@Test func theNightWindowHoldsExactlyTheWebsSevenSignals() {
    #expect(JournalCatalogue.inWindow(.priorNight).map(\.id) == [
        "late_meal", "device_in_bed", "shared_bed", "earplugs",
        "sleep_mask", "pet_in_room", "melatonin"
    ])
}

/// Everything the seven do not name belongs to the day. Stated as its own expectation so a
/// new signal has to declare its window rather than inheriting the wrong one by accident.
@Test func everySignalOutsideTheNightBelongsToTheDay() {
    let night = Set(JournalCatalogue.inWindow(.priorNight).map(\.id))
    let day = JournalCatalogue.inWindow(.calendarDay)

    #expect(day.allSatisfy { !night.contains($0.id) })
    #expect(night.count + day.count == JournalCatalogue.all.count)
}

@MainActor
@Test func aNightSignalIsAskedApartFromTheDay() async throws {
    let client = StubJournalClient(
        prefs: try prefs(#"{ "version": 2, "enabled": { "device_in_bed": true, "sauna": true } }"#)
    )
    let store = JournalStore(client: client, tokenProvider: { "token" })

    await store.load()

    #expect(store.priorNightTrackables.map(\.id) == ["device_in_bed"])
    #expect(store.dayTrackables.map(\.id) == ["sauna"])
}

@MainActor
@Test func dayTrackablesAreSortedByCategory() async throws {
    let client = StubJournalClient(
        prefs: try prefs("""
        { "version": 2,
          "enabled": { "sauna": true, "headache": true, "creatine": true, "alcohol": true } }
        """)
    )
    let store = JournalStore(client: client, tokenProvider: { "token" })

    await store.load()

    // .sante (headache) -> .nutrition (alcohol) -> .complement (creatine) -> .bienEtre (sauna)
    #expect(store.dayTrackables.map(\.id) == ["headache", "alcohol", "creatine", "sauna"])
}

/// Caféine, Humeur and Hydratation are values with their own section, so neither list of
/// yes / no answers may carry them.
@MainActor
@Test func theDayMetricsAreInNeitherFactorList() async throws {
    let client = StubJournalClient(
        prefs: try prefs("""
        { "version": 2,
          "enabled": { "metric_caffeine": true, "metric_mood": true,
                       "metric_hydration": true, "late_meal": true } }
        """)
    )
    let store = JournalStore(client: client, tokenProvider: { "token" })

    await store.load()

    #expect(store.visibleTrackables.count == 4)
    #expect(store.priorNightTrackables.map(\.id) == ["late_meal"])
    #expect(store.dayTrackables.isEmpty)
}

// MARK: - The automatic checklist

private func daySignals(_ json: String) throws -> V1JournalDaySignals {
    try JSONDecoder().decode(V1JournalDaySignals.self, from: Data(json.utf8))
}

@Test func theChecklistDecodesTheWebsPayload() throws {
    let signals = try daySignals("""
    { "trainingDayId": "2026-09-21",
      "checklist": [
        { "id": "steps_10k", "label": "Pas (objectif)", "status": "missed",
          "detail": "3 815 / 10 000" },
        { "id": "stress_ok", "label": "Stress sous cible", "status": "done", "detail": "20 / ≤ 40" },
        { "id": "outdoor_minutes", "label": "Temps outdoor", "status": "unavailable",
          "detail": "Données absentes" }
      ],
      "nutrition": null,
      "dietLabels": [] }
    """)

    #expect(signals.trainingDayId == "2026-09-21")
    #expect(signals.checklist.map(\.id) == ["steps_10k", "stress_ok", "outdoor_minutes"])
    #expect(signals.checklist[0].status == .missed)
    #expect(signals.checklist[1].detail == "20 / ≤ 40")
    #expect(signals.checklist[2].status == .unavailable)
}

/// A line the app cannot read must cost that line, not the whole checklist — the web may
/// ship a fourth status before the app models it.
@Test func anUnknownStatusDropsOnlyItsOwnLine() throws {
    let signals = try daySignals("""
    { "checklist": [
        { "id": "nap", "label": "Sieste", "status": "sometime", "detail": "?" },
        { "id": "cardio_20", "label": "Cardio", "status": "done", "detail": "71 min / ≥ 20 min" }
      ] }
    """)

    #expect(signals.checklist.map(\.id) == ["cardio_20"])
}

@Test func aLineWithoutADetailIsStillRead() throws {
    let signals = try daySignals(#"{ "checklist": [{ "id": "nap", "label": "Sieste", "status": "done" }] }"#)

    #expect(signals.checklist.first?.detail == nil)
}

/// The catalogue and the id list are two places naming the same nine lines, so they are
/// pinned to each other — and to the web's order, which is the render order.
@Test func theAutomaticLinesMatchTheWebsOrder() {
    #expect(JournalAutoItem.ids == [
        "steps_10k", "stress_ok", "nap", "cardio_20", "strength_20",
        "sleep_target", "body_battery_ok", "hydration_sync", "outdoor_minutes"
    ])
    #expect(JournalCatalogue.inCategory(.automatique).map(\.id) == JournalAutoItem.ids)
    #expect(JournalCatalogue.inCategory(.automatique).allSatisfy { $0.kind == .auto })
}

@Test func theChecklistIsOnlyWorthAskingForWhenALineIsOn() throws {
    #expect(!JournalPrefs.empty.hasAnyAutoItem)
    #expect(try prefs(#"{ "version": 2, "enabled": { "alcohol": true } }"#).hasAnyAutoItem == false)
    #expect(try prefs(#"{ "version": 2, "enabled": { "sleep_target": true } }"#).hasAnyAutoItem)
}

@MainActor
@Test func aChecklistLineIsReadAndShown() async throws {
    let client = StubJournalClient(
        prefs: try prefs(#"{ "version": 2, "enabled": { "steps_10k": true } }"#),
        signals: try daySignals("""
        { "checklist": [{ "id": "steps_10k", "label": "Pas (objectif)",
                          "status": "missed", "detail": "3 815 / 10 000" }] }
        """)
    )
    let store = JournalStore(client: client, tokenProvider: { "token" })

    await store.load()

    #expect(store.checklist.map(\.label) == ["Pas (objectif)"])
    // An athlete who enabled only a derived line still has something to read.
    #expect(!store.hasNothingToShow)
}

/// An athlete with no derived line enabled must not pay for a request whose answer would
/// render nothing.
@MainActor
@Test func noDerivedLineMeansNoRequest() async throws {
    let client = StubJournalClient(
        prefs: try prefs(#"{ "version": 2, "enabled": { "alcohol": true } }"#)
    )
    let store = JournalStore(client: client, tokenProvider: { "token" })

    await store.load()

    #expect(await client.signalReadCount() == 0)
    #expect(store.checklist.isEmpty)
}

/// The checklist is the one part of the screen the athlete cannot act on, so losing it must
/// not cost them the part they can.
@MainActor
@Test func aFailedChecklistLeavesTheJournalUsable() async throws {
    let client = StubJournalClient(
        entry: V1DayJournalEntry(trainingDayId: "2026-09-21", factors: ["alcohol": .yes]),
        prefs: try prefs(#"{ "version": 2, "enabled": { "steps_10k": true, "alcohol": true } }"#),
        signals: nil
    )
    let store = JournalStore(client: client, tokenProvider: { "token" })

    await store.load()

    #expect(await client.signalReadCount() == 1)
    #expect(store.phase == .ready)
    #expect(store.checklist.isEmpty)
    #expect(store.entry.state(of: "alcohol") == .yes)
}

// MARK: - Opening on the cached day

@MainActor
private func journalCache() throws -> ModelContext {
    try ModelContext(SharpitPersistence.makeContainer(inMemory: true))
}

@MainActor
@Test func aCachedDayIsReadBackWhole() throws {
    let context = try journalCache()
    let entry = V1DayJournalEntry(
        trainingDayId: "2026-09-21",
        factors: ["alcohol": .yes, "sauna": .no],
        hydrationMl: 1500,
        caffeineMg: 80
    )

    try JournalSnapshotRepository.save(
        trainingDayId: "2026-09-21",
        entry: entry,
        prefs: try prefs(#"{ "version": 2, "enabled": { "alcohol": true } }"#),
        signals: try daySignals(#"{ "checklist": [{ "id": "nap", "label": "Sieste", "status": "done" }] }"#),
        context: context
    )
    let cached = try JournalSnapshotRepository.load(trainingDayId: "2026-09-21", context: context)

    #expect(cached.entry == entry)
    #expect(cached.prefs?.isEnabled("alcohol") == true)
    #expect(cached.signals?.checklist.map(\.id) == ["nap"])
}

@MainActor
@Test func anUncachedDayReadsAsEmptyRatherThanFailing() throws {
    let cached = try JournalSnapshotRepository.load(
        trainingDayId: "2026-09-21",
        context: try journalCache()
    )

    #expect(cached.isEmpty)
}

/// CloudKit refuses a `#Unique` constraint, so uniqueness is enforced on read. Two rows for
/// one day must collapse to the newest, not accumulate.
@MainActor
@Test func aDayNeverKeepsTwoRows() throws {
    let context = try journalCache()
    context.insert(JournalDaySnapshot(
        trainingDayId: "2026-09-21",
        fetchedAt: Date(timeIntervalSince1970: 1_000_000),
        entryJSON: try JSONEncoder().encode(V1DayJournalEntry(trainingDayId: "2026-09-21", caffeineMg: 40))
    ))
    context.insert(JournalDaySnapshot(
        trainingDayId: "2026-09-21",
        fetchedAt: Date(timeIntervalSince1970: 2_000_000),
        entryJSON: try JSONEncoder().encode(V1DayJournalEntry(trainingDayId: "2026-09-21", caffeineMg: 80))
    ))
    try context.save()

    let cached = try JournalSnapshotRepository.load(trainingDayId: "2026-09-21", context: context)

    #expect(cached.entry?.caffeineMg == 80)
    #expect(try context.fetch(FetchDescriptor<JournalDaySnapshot>()).count == 1)
}

/// A save that carries only an entry must not wipe the preferences beside it: the two reads
/// can fail independently.
@MainActor
@Test func savingOnePayloadLeavesTheOthers() throws {
    let context = try journalCache()
    try JournalSnapshotRepository.save(
        trainingDayId: "2026-09-21",
        prefs: try prefs(#"{ "version": 2, "enabled": { "sauna": true } }"#),
        context: context
    )
    try JournalSnapshotRepository.save(
        trainingDayId: "2026-09-21",
        entry: V1DayJournalEntry(trainingDayId: "2026-09-21", caffeineMg: 120),
        context: context
    )

    let cached = try JournalSnapshotRepository.load(trainingDayId: "2026-09-21", context: context)

    #expect(cached.entry?.caffeineMg == 120)
    #expect(cached.prefs?.isEnabled("sauna") == true)
}

@MainActor
@Test func aSecondVisitOpensOnContentRatherThanASkeleton() async throws {
    let context = try journalCache()
    let client = StubJournalClient(
        entry: V1DayJournalEntry(trainingDayId: "2026-09-21", factors: ["sauna": .yes]),
        prefs: try prefs(#"{ "version": 2, "enabled": { "sauna": true } }"#)
    )
    let first = JournalStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-21",
        modelContext: context
    )
    await first.load()

    let second = JournalStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-21",
        modelContext: context
    )
    // Read before any await, so this is the state the first frame renders.
    #expect(second.phase == .loading)
    async let reload: Void = second.load()
    await reload

    #expect(second.phase == .ready)
    #expect(second.entry.state(of: "sauna") == .yes)
}

/// Offline on a painted cache: the athlete keeps yesterday's answers and gets a quiet notice,
/// not an error screen that throws the content away.
@MainActor
@Test func aFailedRefreshKeepsTheCachedDay() async throws {
    let context = try journalCache()
    try JournalSnapshotRepository.save(
        trainingDayId: "2026-09-21",
        entry: V1DayJournalEntry(trainingDayId: "2026-09-21", factors: ["alcohol": .yes]),
        prefs: try prefs(#"{ "version": 2, "enabled": { "alcohol": true } }"#),
        context: context
    )
    let store = JournalStore(
        client: FailingJournalClient(),
        tokenProvider: { "token" },
        trainingDayId: "2026-09-21",
        modelContext: context
    )

    await store.load()

    #expect(store.phase == .ready)
    #expect(store.entry.state(of: "alcohol") == .yes)
    #expect(store.saveFailure != nil)
}

/// Without a cache there is nothing to keep, so a failed load is still a failed screen.
@MainActor
@Test func aFailedFirstLoadStillFails() async throws {
    let store = JournalStore(
        client: FailingJournalClient(),
        tokenProvider: { "token" },
        trainingDayId: "2026-09-21",
        modelContext: try journalCache()
    )

    await store.load()

    #expect(store.phase == .failed("Ton journal n'a pas pu être chargé."))
}

private struct FailingJournalClient: JournalServing {
    func dayJournal(trainingDayId _: String, token _: String) async throws -> V1DayJournalEntry {
        throw SharpitAPIError.transport
    }

    func saveDayJournal(_ entry: V1DayJournalEntry, token _: String) async throws -> V1DayJournalEntry {
        throw SharpitAPIError.transport
    }

    func journalDaySignals(trainingDayId _: String, token _: String) async throws -> V1JournalDaySignals {
        throw SharpitAPIError.transport
    }

    func journalPrefs(token _: String) async throws -> (prefs: JournalPrefs, isPro: Bool) {
        throw SharpitAPIError.transport
    }

    func saveJournalPrefs(
        _ prefs: JournalPrefs,
        token _: String
    ) async throws -> (prefs: JournalPrefs, isPro: Bool) {
        throw SharpitAPIError.transport
    }
}

/// A checklist already on screen must survive a failed refresh, or the athlete watches it
/// vanish — and the cache would then be rewritten empty.
@MainActor
@Test func aPaintedChecklistSurvivesAFailedRefresh() async throws {
    let context = try journalCache()
    try JournalSnapshotRepository.save(
        trainingDayId: "2026-09-21",
        entry: V1DayJournalEntry(trainingDayId: "2026-09-21"),
        prefs: try prefs(#"{ "version": 2, "enabled": { "steps_10k": true } }"#),
        signals: try daySignals("""
        { "checklist": [{ "id": "steps_10k", "label": "Pas (objectif)",
                          "status": "missed", "detail": "3 815 / 10 000" }] }
        """),
        context: context
    )
    // Reads succeed, only the derived route fails.
    let client = StubJournalClient(
        entry: V1DayJournalEntry(trainingDayId: "2026-09-21"),
        prefs: try prefs(#"{ "version": 2, "enabled": { "steps_10k": true } }"#),
        signals: nil
    )
    let store = JournalStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-21",
        modelContext: context
    )

    await store.load()

    #expect(store.checklist.map(\.id) == ["steps_10k"])
    // And the cache still holds it, rather than having been overwritten with nothing.
    let cached = try JournalSnapshotRepository.load(trainingDayId: "2026-09-21", context: context)
    #expect(cached.signals?.checklist.map(\.id) == ["steps_10k"])
}

/// Turning every derived line off is not a failure: the section goes away, so a cached line
/// must not linger.
@MainActor
@Test func disablingEveryDerivedLineClearsTheChecklist() async throws {
    let context = try journalCache()
    try JournalSnapshotRepository.save(
        trainingDayId: "2026-09-21",
        signals: try daySignals(#"{ "checklist": [{ "id": "nap", "label": "Sieste", "status": "done" }] }"#),
        context: context
    )
    let client = StubJournalClient(
        entry: V1DayJournalEntry(trainingDayId: "2026-09-21"),
        prefs: try prefs(#"{ "version": 2, "enabled": { "alcohol": true } }"#)
    )
    let store = JournalStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-21",
        modelContext: context
    )

    await store.load()

    #expect(store.checklist.isEmpty)
}

// MARK: - Date Selection & New Metrics

@MainActor
@Test func setCaffeineAndSetHydrationStoreExactValues() async {
    let store = JournalStore(
        client: StubJournalClient(),
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20",
        saveDelay: .seconds(60)
    )
    await store.load()

    store.setCaffeine(160)
    store.setHydration(1250)

    #expect(store.entry.caffeineMg == 160)
    #expect(store.entry.hydrationMl == 1250)

    store.setCaffeine(-10)
    #expect(store.entry.caffeineMg == 0)
}

@Test func entryHasAnyAnswerReturnsTrueWhenAnyDataPresent() {
    var entry = V1DayJournalEntry(trainingDayId: "2026-09-20")
    #expect(!entry.hasAnyAnswer)

    entry.factors["alcohol"] = .yes
    #expect(entry.hasAnyAnswer)

    entry.factors.removeAll()
    #expect(!entry.hasAnyAnswer)

    entry.moodLabel = "Bien"
    #expect(entry.hasAnyAnswer)

    entry.moodLabel = nil
    entry.caffeineMg = 80
    #expect(entry.hasAnyAnswer)

    entry.caffeineMg = 0
    entry.hydrationMl = 500
    #expect(entry.hasAnyAnswer)
}

@MainActor
@Test func selectDateChangesSelectedDateAndFlushesPending() async {
    let client = StubJournalClient()
    let store = JournalStore(
        client: client,
        tokenProvider: { "token" },
        trainingDayId: "2026-09-20",
        saveDelay: .seconds(60)
    )
    await store.load()

    store.set(factorId: "alcohol", to: .yes)

    let newDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await store.selectDate(newDate)

    #expect(Calendar.current.isDate(store.selectedDate, inSameDayAs: newDate))
    #expect(await client.saveCount() == 1)
}

