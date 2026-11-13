import Foundation

/// Where a value sits against the lab's own bounds — the web's `bloodMarkerStatus`.
nonisolated enum BloodMarkerStatus: Equatable, Sendable {
    case inRange, low, high, noReference

    init(value: Double, refLow: Double?, refHigh: Double?) {
        if refLow == nil, refHigh == nil {
            self = .noReference
        } else if let refLow, value < refLow {
            self = .low
        } else if let refHigh, value > refHigh {
            self = .high
        } else {
            self = .inRange
        }
    }
}

/// What was read from a report, as the athlete corrects it before anything is sent. Nothing of
/// the document survives here but the sampling date and the results.
nonisolated struct BloodTestDraft: Equatable, Sendable {
    struct Row: Identifiable, Equatable, Sendable {
        let markerKey: String
        /// Nil while the athlete has emptied the field.
        var value: Double?
        var refLow: Double?
        var refHigh: Double?

        var id: String { markerKey }
        var marker: BloodMarker? { BloodMarkerCatalog.marker(markerKey) }

        /// False for a value no living adult shows — a lost decimal comma, the wrong line read.
        var isPlausible: Bool {
            guard let value, let marker else { return false }
            return marker.plausible.contains(value)
        }

        var status: BloodMarkerStatus? {
            value.map { BloodMarkerStatus(value: $0, refLow: refLow, refHigh: refHigh) }
        }
    }

    var sampledAt: Date
    var rows: [Row]
    /// True when a recogniser read the text: every figure is then to be checked by eye.
    let isRecognised: Bool

    init(_ report: ParsedBloodReport, now: Date = .now) {
        sampledAt = report.sampledAt ?? now
        rows = report.results.map { Row(markerKey: $0.markerKey, value: $0.value, refLow: $0.refLow, refHigh: $0.refHigh) }
        isRecognised = report.results.contains { $0.confidence < 1 }
    }

    var canSave: Bool {
        !rows.isEmpty && rows.allSatisfy(\.isPlausible)
    }

    /// The catalog's markers the report did not yield, for the athlete to add by hand.
    var missingMarkers: [BloodMarker] {
        BloodMarkerCatalog.all.filter { marker in !rows.contains { $0.markerKey == marker.key } }
    }

    mutating func add(_ marker: BloodMarker) {
        guard !rows.contains(where: { $0.markerKey == marker.key }) else { return }
        rows.append(Row(markerKey: marker.key, value: nil))
    }

    var inputs: [BloodTestResultInput] {
        rows.compactMap { row in
            guard let value = row.value, let marker = row.marker else { return nil }
            return BloodTestResultInput(markerKey: row.markerKey, value: value, unit: marker.unit,
                                        refLow: row.refLow, refHigh: row.refHigh)
        }
    }
}
