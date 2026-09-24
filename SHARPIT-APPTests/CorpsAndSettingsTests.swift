import Foundation
import SwiftUI
import Testing
@testable import Sharpit

// MARK: - Corps readout

private func weighIn(_ daysAgo: Double, weight: Double?, fat: Double? = nil, source: String = "WITHINGS") -> V1BodyMeasurement {
    V1BodyMeasurement(
        id: "m\(daysAgo)",
        measuredAt: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400),
        source: source,
        weightKg: weight,
        bodyFatPct: fat
    )
}

@Test func corpsShowsOnlyWhatWasMeasured() throws {
    let recovery = try JSONDecoder().decode(V1RecoveryResponse.self, from: Data(recoveryJSON.utf8))
    let metrics = CorpsReadout.metrics(
        profile: V1AthleteProfile(ftpW: 250, maxHr: 188, vo2maxRunning: 54),
        measurements: [weighIn(0, weight: 72.4, fat: 15), weighIn(10, weight: 73.0, fat: 16)],
        recovery: recovery,
        thresholds: []
    )

    #expect(metrics.map(\.key) == [.weight, .hrv, .restingHr, .vo2maxRun, .bodyFatPct, .leanMassKg, .ftp, .maxHr])
}

@Test func theWeightReadsAgainstAWeighInAWeekOlder() {
    let metrics = CorpsReadout.metrics(
        profile: nil,
        measurements: [weighIn(0, weight: 72.4), weighIn(1, weight: 72.9), weighIn(9, weight: 73.4)],
        recovery: nil,
        thresholds: []
    )
    let weight = metrics.first { $0.key == .weight }

    #expect(weight?.formattedValue == "72,4")
    #expect(weight?.note == "−1,0 kg sur 7 j")
    #expect(weight?.series.map(\.value) == [73.4, 72.9, 72.4])
    #expect(weight?.source == "Withings")
}

@Test func leanMassIsWeightWithoutFat() throws {
    let metrics = CorpsReadout.metrics(
        profile: nil,
        measurements: [weighIn(0, weight: 80, fat: 20)],
        recovery: nil,
        thresholds: []
    )

    let lean = try #require(metrics.first { $0.key == .leanMassKg })
    #expect(abs(lean.value - 64) < 0.001)
}

@Test func hrvCarriesItsBandAndReadsBelowIt() throws {
    let low = recoveryJSON.replacingOccurrences(of: #""today": { "hrv": 58"#, with: #""today": { "hrv": 50"#)
        .replacingOccurrences(of: #"{ "date": "2026-09-21", "hrv": 58"#, with: #"{ "date": "2026-09-21", "hrv": 50"#)
    let recovery = try JSONDecoder().decode(V1RecoveryResponse.self, from: Data(low.utf8))

    let hrv = CorpsReadout.recoveryMetrics(recovery).first { $0.key == .hrv }

    #expect(hrv?.baseline == 55...70)
    #expect(hrv?.tone == .belowRange)
    #expect(hrv?.note == "plage 55–70")
    #expect(hrv?.series.count == 3)
}

@Test func paceThresholdsReadAsMinutesAndSeconds() {
    #expect(CorpsReadout.format(255, for: .runThresholdPace) == "4:15")
    #expect(CorpsReadout.format(188.4, for: .maxHr) == "188")
}

@Test func aRangeCountsBackFromTheLatestPoint() {
    let last = Date(timeIntervalSince1970: 1_800_000_000)
    let points = [100, 40, 10, 0].map { CorpsPoint(date: last.addingTimeInterval(-Double($0) * 86_400), value: 1) }

    #expect(CorpsRange.thirtyDays.filter(points).count == 2)
    #expect(CorpsRange.ninetyDays.filter(points).count == 3)
    #expect(CorpsRange.all.filter(points).count == 4)
}

// MARK: - Paramètres

@Test func initialsComeFromTheNames() {
    #expect(AccountInitials.from(first: "Augustin", last: "Briolon") == "AB")
    #expect(AccountInitials.from(first: " gus", last: nil) == "G")
    #expect(AccountInitials.from(first: nil, last: "  ") == "?")
}

@Test func ageIsWholeYears() {
    let calendar = Calendar(identifier: .gregorian)
    let birth = calendar.date(from: DateComponents(year: 1995, month: 10, day: 1))!
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!

    #expect(AccountAge.years(birthDate: birth, now: now, calendar: calendar) == 30)
    #expect(AccountAge.years(birthDate: nil) == nil)
}

@Test func appearanceMapsToAColourScheme() {
    #expect(AppearancePreference.system.colorScheme == nil)
    #expect(AppearancePreference.light.colorScheme == .light)
    #expect(AppearancePreference.dark.colorScheme == .dark)
}

@MainActor
@Test func iCloudKeepsTheLastEventOfEachKindAcrossLaunches() throws {
    let defaults = try #require(UserDefaults(suiteName: "cloud-sync-monitor"))
    defaults.removePersistentDomain(forName: "cloud-sync-monitor")
    let monitor = CloudSyncMonitor(defaults: defaults)

    monitor.record(.init(endedAt: Date(timeIntervalSince1970: 100), succeeded: false, errorDescription: "Quota"), as: .exporting)
    #expect(monitor.lastError == "Quota")

    monitor.record(.init(endedAt: Date(timeIntervalSince1970: 200), succeeded: true, errorDescription: nil), as: .importing)
    #expect(monitor.lastError == nil)

    let relaunched = CloudSyncMonitor(defaults: defaults)
    #expect(relaunched.events[.exporting]?.errorDescription == "Quota")
    #expect(relaunched.events[.importing]?.succeeded == true)
}
