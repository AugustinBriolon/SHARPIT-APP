import Foundation

/// Stable frein codes the Today / Recovery chip may receive.
///
/// Unknown or null codes hide the chip entry — never invent a label. Labels are localized
/// in-app (essential / expert) from `verdict-copy.snapshot.json`, not from the wire.
nonisolated enum LimiterSignalCode: Equatable, Hashable, Sendable {
    case hrvLow
    case rhrHigh
    case sleepShort
    case sleepPoor
    case subjectiveLow
    case loadElevated
    case unknown(String)

    /// Ordered codes the snapshot / server glossary knows — used by exhaustive tests.
    static let knownOrdered: [LimiterSignalCode] = [
        .hrvLow, .rhrHigh, .sleepShort, .sleepPoor, .subjectiveLow, .loadElevated,
    ]

    var wireValue: String? {
        switch self {
        case .hrvLow: "hrv_low"
        case .rhrHigh: "rhr_high"
        case .sleepShort: "sleep_short"
        case .sleepPoor: "sleep_poor"
        case .subjectiveLow: "subjective_low"
        case .loadElevated: "load_elevated"
        case .unknown: nil
        }
    }

    var isKnown: Bool {
        wireValue != nil
    }

    init(wire: String) {
        switch wire {
        case "hrv_low": self = .hrvLow
        case "rhr_high": self = .rhrHigh
        case "sleep_short": self = .sleepShort
        case "sleep_poor": self = .sleepPoor
        case "subjective_low": self = .subjectiveLow
        case "load_elevated": self = .loadElevated
        default: self = .unknown(wire)
        }
    }

    /// Essential / expert pair — nil for unknown.
    func labels() -> (essential: String, expert: String)? {
        switch self {
        case .hrvLow: (String(localized: "Corps pas encore récupéré"), String(localized: "VFC basse"))
        case .rhrHigh: (String(localized: "Cœur plus rapide au repos"), String(localized: "FC repos haute"))
        case .sleepShort: (String(localized: "Nuit trop courte"), String(localized: "Sommeil court"))
        case .sleepPoor: (String(localized: "Nuit agitée"), String(localized: "Sommeil agité"))
        case .subjectiveLow: (String(localized: "Fatigue ressentie"), String(localized: "Ressenti bas"))
        case .loadElevated: (String(localized: "Grosse semaine d’entraînement"), String(localized: "Charge élevée"))
        case .unknown: nil
        }
    }

    func label(isExpert: Bool) -> String? {
        guard let pair = labels() else { return nil }
        return isExpert ? pair.expert : pair.essential
    }
}

extension LimiterSignalCode: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .unknown("")
            return
        }
        self = LimiterSignalCode(wire: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unknown(let raw): try container.encode(raw)
        default: try container.encode(wireValue ?? "")
        }
    }
}

/// « Porté par » codes — what held up overnight. Unknown wire values are dropped, never labelled.
nonisolated enum SupportSignalCode: String, Sendable, CaseIterable {
    case hrvOk = "hrv_ok"
    case rhrOk = "rhr_ok"
    case sleepAdequate = "sleep_adequate"
    case sleepQualityOk = "sleep_quality_ok"
    case subjectiveOk = "subjective_ok"
    case loadManaged = "load_managed"

    func label(isExpert: Bool) -> String {
        switch self {
        case .hrvOk: isExpert ? String(localized: "VFC dans la norme") : String(localized: "Corps bien récupéré")
        case .rhrOk: isExpert ? String(localized: "FC repos normale") : String(localized: "Cœur calme au repos")
        case .sleepAdequate: isExpert ? String(localized: "Sommeil suffisant") : String(localized: "Nuit suffisante")
        case .sleepQualityOk: isExpert ? String(localized: "Sommeil de qualité") : String(localized: "Nuit réparatrice")
        case .subjectiveOk: isExpert ? String(localized: "Ressenti élevé") : String(localized: "Bonne forme ressentie")
        case .loadManaged: isExpert ? String(localized: "Charge maîtrisée") : String(localized: "Charge bien gérée")
        }
    }
}

/// Frein chip copy for the verdict plate — density-aware, never jargon defaults.
nonisolated enum LimiterChipCopy {
    static let prefix = String(localized: "Frein")

    /// Nil when there is nothing known to show (empty, null, or only unknown codes).
    static func text(codes: [LimiterSignalCode], isExpert: Bool) -> String? {
        let known = codes.filter(\.isKnown)
        guard !known.isEmpty else { return nil }
        if known.count == 1, let label = known[0].label(isExpert: isExpert) {
            return "\(prefix) · \(label)"
        }
        if isExpert {
            let joined = known.compactMap { $0.label(isExpert: true) }.joined(separator: ", ")
            guard !joined.isEmpty else { return nil }
            return "\(prefix) · \(joined)"
        }
        return String(localized: "\(prefix) · \(known.count) signaux")
    }
}
