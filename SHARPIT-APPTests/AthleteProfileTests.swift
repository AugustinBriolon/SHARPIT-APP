import Foundation
import Testing
@testable import Sharpit

// MARK: - Patch semantics

/// The documented data-loss bug: a one-field save must not mention the other fields.
@Test func aPatchCarriesOnlyTheFieldsItWasGiven() throws {
    var patch = AthleteProfilePatch()
    patch.set(.ftpW, int: 215)

    #expect(patch.fields.keys.sorted() == ["ftpW"])
    #expect(patch.fields["ftpW"] == .number(215))
}

@Test func anEmptyPatchIsRecognisedAsEmpty() {
    #expect(AthleteProfilePatch().isEmpty)
}

@Test func clearingAFieldSendsAnExplicitNull() {
    var patch = AthleteProfilePatch()
    patch.set(.targetWeightKg, double: nil)

    #expect(patch.fields["targetWeightKg"] == .null)
}

@Test func anUnchangedFieldIsNotSent() {
    var patch = AthleteProfilePatch()
    patch.setIfChanged(.maxHr, int: 190, was: 190)
    patch.setIfChanged(.lthr, int: 168, was: 165)

    #expect(patch.fields.keys.sorted() == ["lthr"])
}

/// Clearing a field the athlete emptied is a change, so it still has to reach the server.
@Test func emptyingAFieldThatHeldAValueIsSentAsNull() {
    var patch = AthleteProfilePatch()
    patch.setIfChanged(.ftpW, int: nil, was: 240)

    #expect(patch.fields["ftpW"] == .null)
}

@Test func aBlankStringClearsRatherThanWritingAnEmptyValue() {
    var patch = AthleteProfilePatch()
    patch.set(.birthDate, string: "   ")

    #expect(patch.fields["birthDate"] == .null)
}

@Test func theBodySerialisesToJSONWithTheNullKept() throws {
    var patch = AthleteProfilePatch()
    patch.set(.ftpW, int: 215)
    patch.set(.lthr, int: nil)

    let data = try JSONSerialization.data(withJSONObject: patch.body)
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: data)

    #expect(decoded == ["ftpW": .number(215), "lthr": .null])
}

/// The web's patch validator has no `vo2max*` key, so the app must not be able to name one.
@Test func thePatchableFieldsMatchTheWebValidator() {
    let keys = Set(AthleteProfileField.allCases.map(\.rawValue))

    #expect(keys == [
        "displayMode", "heightCm", "birthDate", "targetWeightKg",
        "sleepTargetMinutes", "sleepBedtimeTargetMin",
        "ftpW", "maxHr", "lthr",
        "runThresholdPaceSecPerKm", "swimCssSecPer100m", "defaultPoolLengthM",
        "equipment", "practicedSports",
    ])
}

// MARK: - Decoding

@Test func theProfileDecodesTheFieldsTheAppRenders() throws {
    let json = Data("""
    {
      "displayMode": "expert",
      "tier": "PRO",
      "heightCm": 178,
      "birthDate": "1990-04-12T00:00:00.000Z",
      "targetWeightKg": 71.5,
      "sleepTargetMinutes": 480,
      "sleepBedtimeTargetMin": 1350,
      "ftpW": 245,
      "maxHr": 190,
      "lthr": 168,
      "runThresholdPaceSecPerKm": 255,
      "swimCssSecPer100m": 98,
      "defaultPoolLengthM": 25,
      "vo2maxRunning": 54,
      "thresholdsSyncedAt": "2026-09-18T06:12:04.512Z"
    }
    """.utf8)

    let profile = try JSONDecoder().decode(V1AthleteProfile.self, from: json)

    #expect(profile.isExpertReading)
    #expect(profile.isPro)
    #expect(profile.heightCm == 178)
    #expect(profile.birthDate != nil)
    #expect(profile.sleepBedtimeTargetMin == 1350)
    #expect(profile.runThresholdPaceSecPerKm == 255)
    #expect(profile.vo2maxRunning == 54)
    #expect(profile.thresholdsSyncedAt != nil)
}

/// An athlete with no profile row still gets a density and a tier, and nothing else.
@Test func aProfileWithOnlyADensityDecodes() throws {
    let json = Data(#"{"id":"a1","displayMode":"essential","tier":"FREE"}"#.utf8)

    let profile = try JSONDecoder().decode(V1AthleteProfile.self, from: json)

    #expect(profile.isExpertReading == false)
    #expect(profile.isPro == false)
    #expect(profile.ftpW == nil)
}

/// A date the app cannot read must not take the whole profile down with it.
@Test func anUnreadableDateIsDroppedRatherThanFailingTheProfile() throws {
    let json = Data(#"{"heightCm":178,"birthDate":"12/04/1990"}"#.utf8)

    let profile = try JSONDecoder().decode(V1AthleteProfile.self, from: json)

    #expect(profile.heightCm == 178)
    #expect(profile.birthDate == nil)
}

@Test func aWeighInDecodesAndNamesItsScale() throws {
    let json = Data("""
    [
      {
        "id": "m2",
        "measuredAt": "2026-09-20T06:40:00.000Z",
        "source": "WITHINGS",
        "weightKg": 72.4,
        "bodyFatPct": 14.2,
        "musclePct": 42.1,
        "waterPct": 58.3,
        "boneKg": 3.1,
        "bmi": 22.4,
        "vascularAgeYears": 31
      }
    ]
    """.utf8)

    let measurements = try JSONDecoder().decode([V1BodyMeasurement].self, from: json)

    #expect(measurements.count == 1)
    #expect(measurements[0].weightKg == 72.4)
    #expect(measurements[0].source == "WITHINGS")
    #expect(measurements[0].bmi == 22.4)
}

@Test func aThresholdSnapshotNamesWhoSetIt() throws {
    let json = Data("""
    [
      { "id": "s1", "createdAt": "2026-09-18T06:12:04.512Z", "source": "garmin", "ftpW": 245 },
      { "id": "s2", "createdAt": "2026-08-01T09:00:00.000Z", "source": "estimated", "lthr": 165 },
      { "id": "s3", "createdAt": "2026-07-01T09:00:00.000Z", "source": "manual", "ftpW": 230 }
    ]
    """.utf8)

    let snapshots = try JSONDecoder().decode([V1ThresholdSnapshot].self, from: json)

    #expect(snapshots.map(\.sourceLabel) == ["Importé de Garmin", "Estimé", "Saisi à la main"])
}

// MARK: - Field formats

@Test func aPaceRoundTripsBetweenSecondsAndTheTypedValue() {
    #expect(ProfileFieldFormat.pace(255) == "4:15")
    #expect(ProfileFieldFormat.parsePace("4:15") == 255)
    // A swim CSS is the same format, per 100 m.
    #expect(ProfileFieldFormat.pace(98) == "1:38")
    #expect(ProfileFieldFormat.parsePace("1:38") == 98)
}

@Test func aHalfTypedPaceDoesNotParse() {
    #expect(ProfileFieldFormat.parsePace("4") == nil)
    #expect(ProfileFieldFormat.parsePace("4:") == nil)
    #expect(ProfileFieldFormat.parsePace("4:75") == nil)
    #expect(ProfileFieldFormat.parsePace("") == nil)
}

@Test func anUnsetThresholdReadsAsAnEmptyField() {
    #expect(ProfileFieldFormat.pace(nil).isEmpty)
    #expect(ProfileFieldFormat.pace(0).isEmpty)
    #expect(ProfileFieldFormat.integer(nil).isEmpty)
    #expect(ProfileFieldFormat.decimal(nil).isEmpty)
}

@Test func aBedtimeRoundTripsAsATimeOfDay() {
    #expect(ProfileFieldFormat.clock(1350) == "22:30")
    #expect(ProfileFieldFormat.parseClock("22:30") == 1350)
    #expect(ProfileFieldFormat.parseClock("06:05") == 365)
}

@Test func aBedtimePastTheDayDoesNotParse() {
    #expect(ProfileFieldFormat.parseClock("24:00") == nil)
    #expect(ProfileFieldFormat.parseClock("22:60") == nil)
}

@Test func aSleepTargetReadsAsADurationNotAClock() {
    #expect(ProfileFieldFormat.duration(510) == "8 h 30")
    #expect(ProfileFieldFormat.duration(480) == "8 h")
    #expect(ProfileFieldFormat.duration(45) == "45 min")
}

@Test func aWeightIsWrittenAndReadWithTheFrenchComma() {
    #expect(ProfileFieldFormat.decimal(71.5) == "71,5")
    #expect(ProfileFieldFormat.parseDecimal("71,5") == 71.5)
    #expect(ProfileFieldFormat.parseDecimal("71.5") == 71.5)
    #expect(ProfileFieldFormat.parseDecimal("abc") == nil)
}

// MARK: - Form state

private let loadedProfile = V1AthleteProfile(
    displayMode: "essential",
    heightCm: 178,
    targetWeightKg: 72,
    sleepTargetMinutes: 480,
    sleepBedtimeTargetMin: 1350,
    ftpW: 245,
    maxHr: 190,
    lthr: 168,
    runThresholdPaceSecPerKm: 255,
    swimCssSecPer100m: 98,
    defaultPoolLengthM: 25
)

@Test func aFormFilledFromAProfileHasNothingToSend() {
    let form = ProfileFormState(profile: loadedProfile)

    #expect(form.patch(against: loadedProfile).isEmpty)
    #expect(form.firstError == nil)
}

@Test func onlyTheEditedFieldReachesTheServer() {
    var form = ProfileFormState(profile: loadedProfile)
    form.ftpW = "260"

    let patch = form.patch(against: loadedProfile)

    #expect(patch.fields == ["ftpW": .number(260)])
}

@Test func aClearedFieldIsSentAsNull() {
    var form = ProfileFormState(profile: loadedProfile)
    form.lthr = ""

    #expect(form.patch(against: loadedProfile).fields == ["lthr": .null])
}

/// A pace is typed but stored in seconds, so the round trip has to survive being loaded and
/// saved without the athlete touching it.
@Test func aPaceLoadedAndSavedUntouchedSendsNothing() {
    let form = ProfileFormState(profile: loadedProfile)

    #expect(form.patch(against: loadedProfile).fields["runThresholdPaceSecPerKm"] == nil)
    #expect(form.runThresholdPace == "4:15")
    #expect(form.swimCss == "1:38")
}

@Test func anEditedPaceIsSentInSeconds() {
    var form = ProfileFormState(profile: loadedProfile)
    form.runThresholdPace = "4:05"

    #expect(form.patch(against: loadedProfile).fields == ["runThresholdPaceSecPerKm": .number(245)])
}

/// The server stores minutes; the athlete types hours. A half hour has to survive both ways.
@Test func aSleepTargetIsTypedInHoursAndSentInMinutes() {
    var form = ProfileFormState(profile: loadedProfile)
    #expect(form.sleepTargetHours == "8,0")

    form.sleepTargetHours = "8,5"

    #expect(form.patch(against: loadedProfile).fields == ["sleepTargetMinutes": .number(510)])
}

/// A `@db.Date` compared by instant would resend the same day on every save.
@Test func anUntouchedBirthDateIsNotResent() {
    let profile = V1AthleteProfile(birthDate: Date(timeIntervalSince1970: 640_000_000))
    let form = ProfileFormState(profile: profile)

    #expect(form.patch(against: profile).isEmpty)
}

@Test func aBirthDateIsSentAsACalendarDay() {
    var form = ProfileFormState(profile: V1AthleteProfile())
    form.birthDate = Date(timeIntervalSince1970: 640_000_000)

    #expect(form.patch(against: V1AthleteProfile()).fields == ["birthDate": .string("1990-04-13")])
}

@Test func anEntryThatIsNotANumberRefusesTheSave() {
    var form = ProfileFormState(profile: loadedProfile)
    form.maxHr = "cent quatre-vingt-dix"

    #expect(form.error(for: .maxHr) != nil)
    #expect(form.firstError?.field == .maxHr)
}

@Test func aValueOutsideTheWebBoundsIsRefused() {
    var form = ProfileFormState(profile: loadedProfile)
    form.heightCm = "40"
    #expect(form.error(for: .heightCm) != nil)

    form.heightCm = "178"
    form.poolLength = "500"
    #expect(form.error(for: .poolLength) != nil)

    form.poolLength = "50"
    form.sleepTargetHours = "20"
    #expect(form.error(for: .sleepTargetHours) != nil)
}

/// An emptied field clears the value; it is not an error.
@Test func anEmptyFieldReadsAsValid() {
    var form = ProfileFormState(profile: loadedProfile)
    for field in ProfileFormField.allCases {
        #expect(form.error(for: field) == nil)
    }
    form.ftpW = ""
    #expect(form.error(for: .ftpW) == nil)
}

// MARK: - Body composition

private actor StubBodyClient: BodyCompositionServing {
    private let measurements: [V1BodyMeasurement]
    private let fails: Bool

    init(_ measurements: [V1BodyMeasurement], fails: Bool = false) {
        self.measurements = measurements
        self.fails = fails
    }

    func bodyComposition(days _: Int, token _: String) async throws -> [V1BodyMeasurement] {
        if fails { throw SharpitAPIError.server }
        return measurements
    }
}

private func weighIn(_ daysAgo: Int, _ weightKg: Double) -> V1BodyMeasurement {
    V1BodyMeasurement(
        id: "m\(daysAgo)",
        measuredAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(daysAgo) * 86_400),
        source: "WITHINGS",
        weightKg: weightKg
    )
}

@MainActor
@Test func theStoreKeepsTheLatestWeighInAndAWeekOldReference() async {
    let store = BodyCompositionStore(
        client: StubBodyClient([weighIn(0, 72.4), weighIn(1, 72.6), weighIn(10, 74.0)]),
        tokenProvider: { "t" }
    )

    await store.load()

    #expect(store.phase == .loaded)
    #expect(store.latest?.weightKg == 72.4)
    // Not yesterday's: two consecutive mornings differ by water, not by composition.
    #expect(store.reference?.weightKg == 74.0)
}

@MainActor
@Test func noWeighInIsEmptyRatherThanFailed() async {
    let store = BodyCompositionStore(client: StubBodyClient([]), tokenProvider: { "t" })

    await store.load()

    #expect(store.phase == .empty)
    #expect(store.latest == nil)
}

@MainActor
@Test func aFailedReadSaysSo() async {
    let store = BodyCompositionStore(client: StubBodyClient([], fails: true), tokenProvider: { "t" })

    await store.load()

    #expect(store.phase == .failed("Lecture de tes mesures impossible."))
}

@Test func onlyTheMetricsTheScaleWroteBecomeTiles() {
    let full = V1BodyMeasurement(
        id: "m1",
        measuredAt: .now,
        weightKg: 72.4,
        bodyFatPct: 14.2,
        musclePct: 42.1,
        waterPct: 58.3,
        boneKg: 3.1,
        bmi: 22.4
    )
    #expect(BodyCompositionReadout.tiles(full).map(\.caption)
            == ["Masse grasse", "Muscle", "Eau corporelle", "Masse osseuse", "IMC"])

    // A scale that only weighs must not show five empty tiles.
    let weightOnly = V1BodyMeasurement(id: "m2", measuredAt: .now, weightKg: 72.4)
    #expect(BodyCompositionReadout.tiles(weightOnly).isEmpty)
}

@Test func anUnknownScaleIsNotNamed() {
    #expect(BodyCompositionReadout.scaleLabel("WITHINGS") == "Withings")
    #expect(BodyCompositionReadout.scaleLabel("garmin") == "Garmin")
    #expect(BodyCompositionReadout.scaleLabel("some-new-provider") == nil)
    #expect(BodyCompositionReadout.scaleLabel(nil) == nil)
}

@Test func aWeightMoveUnderTheScalesPrecisionReadsAsStable() {
    let trend = BodyTrend.weight(latest: weighIn(0, 72.4), reference: weighIn(10, 72.5))

    #expect(trend?.label == "Stable")
}

@Test func aWeightMoveIsStatedWithoutAVerdict() {
    let down = BodyTrend.weight(latest: weighIn(0, 72.4), reference: weighIn(10, 74.0))
    let up = BodyTrend.weight(latest: weighIn(0, 74.0), reference: weighIn(10, 72.4))

    #expect(down?.label == "−1,6 kg")
    #expect(up?.label == "+1,6 kg")
    // Neutral both ways: SHARPIT does not know whether this athlete is cutting or building.
    #expect(down?.tone == up?.tone)
}

@Test func withoutAReferenceThereIsNoTrend() {
    #expect(BodyTrend.weight(latest: weighIn(0, 72.4), reference: nil) == nil)
}

// MARK: - Reading density

private actor StubProfileClient: AthleteProfileServing {
    private let profile: V1AthleteProfile
    private let fails: Bool
    private(set) var patches: [AthleteProfilePatch] = []

    init(_ profile: V1AthleteProfile, fails: Bool = false) {
        self.profile = profile
        self.fails = fails
    }

    func athleteProfile(token _: String) async throws -> V1AthleteProfile {
        if fails { throw SharpitAPIError.server }
        return profile
    }

    func patchAthleteProfile(
        _ patch: AthleteProfilePatch,
        token _: String
    ) async throws -> V1AthleteProfile {
        patches.append(patch)
        var saved = profile
        if case .string(let mode) = patch.fields["displayMode"] {
            saved.displayMode = mode
        }
        return saved
    }

    func thresholdHistory(token _: String) async throws -> [V1ThresholdSnapshot] { [] }

    func recordedPatches() -> [AthleteProfilePatch] { patches }
}

@MainActor
@Test func theDensityIsEssentialUntilTheProfileAnswers() {
    let store = DisplayModeStore(client: StubProfileClient(V1AthleteProfile(displayMode: "expert")))

    #expect(store.isExpert == false)
    #expect(store.isResolved == false)
}

@MainActor
@Test func theDensityIsAdoptedFromTheProfile() async {
    let store = DisplayModeStore(client: StubProfileClient(V1AthleteProfile(displayMode: "expert")))

    await store.load(tokenProvider: { "t" })

    #expect(store.isExpert)
    #expect(store.isResolved)
}

/// A screen that cannot learn the density renders the essential reading rather than failing.
@MainActor
@Test func aFailedDensityReadStaysEssential() async {
    let store = DisplayModeStore(client: StubProfileClient(V1AthleteProfile(), fails: true))

    await store.load(tokenProvider: { "t" })

    #expect(store.isExpert == false)
    #expect(store.isResolved == false)
}

@MainActor
@Test func switchingToExpertSavesOnlyTheDensity() async {
    let client = StubProfileClient(V1AthleteProfile(displayMode: "essential", ftpW: 245))
    let store = AthleteProfileStore(client: client, tokenProvider: { "t" })

    await store.load()
    await store.setExpertReading(true)

    #expect(store.isExpertReading)
    // A one-field save must not mention the thresholds beside it.
    #expect(await client.recordedPatches().map(\.fields) == [["displayMode": .string("expert")]])
}
