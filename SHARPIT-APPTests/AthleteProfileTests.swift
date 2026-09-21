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
