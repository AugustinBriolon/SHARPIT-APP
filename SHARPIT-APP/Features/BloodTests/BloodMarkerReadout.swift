import Foundation

/// How a blood result is worded: the lab's interval as it prints it, and where the value sits in it.
nonisolated enum BloodMarkerReadout {
    /// « 4,1 – 10,8 », « < 1,5 », « > 0,4 », or nothing without a bound.
    static func reference(low: Double?, high: Double?) -> String {
        switch (low?.formatted(), high?.formatted()) {
        case let (low?, high?): "\(low) – \(high)"
        case let (nil, high?): "< \(high)"
        case let (low?, nil): "> \(low)"
        case (nil, nil): ""
        }
    }

    /// The line under a marker: its interval, led by « Bas » or « Haut » when the value is outside.
    static func caption(status: BloodMarkerStatus, low: Double?, high: Double?) -> String {
        let reference = reference(low: low, high: high)
        switch status {
        case .low: return String(localized: "Bas · \(reference)")
        case .high: return String(localized: "Haut · \(reference)")
        case .inRange: return reference
        case .noReference: return String(localized: "Sans intervalle")
        }
    }

    static func isOutOfRange(_ status: BloodMarkerStatus) -> Bool {
        status == .low || status == .high
    }

    /// « 1,8 » with its unit, the way a row shows it.
    static func value(_ value: Double, unit: String) -> String {
        "\(value.formatted()) \(unit)"
    }

    /// « +0,12 », « −3 »: the change since the test before, signed with a true minus.
    static func delta(_ delta: Double) -> String {
        let magnitude = abs(delta).formatted()
        return delta > 0 ? "+\(magnitude)" : delta < 0 ? "−\(magnitude)" : "="
    }
}

/// One marker across the athlete's tests, oldest first: what its history screen draws.
nonisolated struct BloodMarkerHistory: Equatable, Sendable {
    struct Point: Identifiable, Equatable, Sendable {
        let testId: String
        let date: Date
        let value: Double
        let refLow: Double?
        let refHigh: Double?

        var id: String { testId }
        var status: BloodMarkerStatus { BloodMarkerStatus(value: value, refLow: refLow, refHigh: refHigh) }
    }

    let markerKey: String
    let points: [Point]

    init(markerKey: String, tests: [V1BloodTest]) {
        self.markerKey = markerKey
        points = tests
            .compactMap { test in
                test.results.first { $0.markerKey == markerKey }.map {
                    Point(testId: test.id, date: test.sampledAt, value: $0.value, refLow: $0.refLow, refHigh: $0.refHigh)
                }
            }
            .sorted { $0.date < $1.date }
    }

    var marker: BloodMarker? { BloodMarkerCatalog.marker(markerKey) }
    var latest: Point? { points.last }

    /// The change between the last two tests that measured it.
    var lastChange: Double? {
        guard points.count > 1 else { return nil }
        return points[points.count - 1].value - points[points.count - 2].value
    }

    /// Markers measured in at least two tests, in the catalog's order: the ones with an evolution.
    static func followed(in tests: [V1BloodTest]) -> [BloodMarkerHistory] {
        BloodMarkerCatalog.all
            .map { BloodMarkerHistory(markerKey: $0.key, tests: tests) }
            .filter { $0.points.count > 1 }
    }
}
