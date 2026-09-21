import Foundation

/// A day signal the athlete records by hand. `unset` is "not answered", which is not
/// the same as `no` — the analyses only count an explicit answer.
nonisolated enum JournalFactorState: String, Codable, Sendable {
    case unset
    case no
    case yes

    /// unset → yes → no → unset, the order the web cycles through.
    var next: JournalFactorState {
        switch self {
        case .unset: .yes
        case .yes: .no
        case .no: .unset
        }
    }
}

nonisolated struct V1DayJournalEntry: Equatable, Sendable {
    var trainingDayId: String
    var factors: [String: JournalFactorState]
    var moodLabel: String?
    var hydrationMl: Int?
    var caffeineMg: Int?

    init(
        trainingDayId: String,
        factors: [String: JournalFactorState] = [:],
        moodLabel: String? = nil,
        hydrationMl: Int? = nil,
        caffeineMg: Int? = 0
    ) {
        self.trainingDayId = trainingDayId
        self.factors = factors
        self.moodLabel = moodLabel
        self.hydrationMl = hydrationMl
        self.caffeineMg = caffeineMg
    }

    func state(of factorId: String) -> JournalFactorState {
        factors[factorId] ?? .unset
    }
}

nonisolated extension V1DayJournalEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case trainingDayId
        case factors
        case moodLabel
        case hydrationMl
        case caffeineMg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trainingDayId = try container.decodeIfPresent(String.self, forKey: .trainingDayId) ?? ""
        // A state the app does not know is dropped rather than failing the whole day:
        // the web may ship a new one before the app models it.
        let raw = try container.decodeIfPresent([String: String].self, forKey: .factors) ?? [:]
        factors = raw.compactMapValues(JournalFactorState.init(rawValue:))
        moodLabel = try container.decodeIfPresent(String.self, forKey: .moodLabel)
        hydrationMl = try container.decodeIfPresent(Int.self, forKey: .hydrationMl)
        caffeineMg = try container.decodeIfPresent(Int.self, forKey: .caffeineMg) ?? 0
    }
}

nonisolated struct V1DayJournalEnvelope: Decodable {
    let entry: V1DayJournalEntry?
}

/// Whether a derived checklist line was met, missed, or could not be read at all.
///
/// `unavailable` is not a failure: it says the device wrote nothing for that signal today,
/// which is what an athlete needs to know before reading the rest of the line.
nonisolated enum JournalAutoStatus: String, Codable, Sendable {
    case done
    case missed
    case unavailable
}

/// One line of the automatic checklist, already decided server-side.
///
/// The threshold comparison, the sport types that count as cardio and the minutes summed per
/// activity all live in the web's `journal-auto-checklist.ts`. The app renders the verdict and
/// never recomputes it: two implementations of the same rule would diverge the first time a
/// threshold moved.
nonisolated struct V1JournalAutoChecklistItem: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let status: JournalAutoStatus
    /// `"3 815 / 10 000"`, or `"Données absentes"` — already formatted and localised by the
    /// server, because the units differ per line and the web writes them all.
    let detail: String?
}

/// The derived half of a journal day: what the devices reported, as opposed to what the
/// athlete answered.
///
/// The route also returns `nutrition` and `dietLabels`. Both stay out: the app has no
/// nutrition panel, and decoding a payload it does not render is an invitation to render it
/// badly.
/// Encodable as well as decodable, because the app writes it back into its own cache — the
/// lenient decode above is for the server's payload, the encode is for the app's.
nonisolated struct V1JournalDaySignals: Codable, Equatable, Sendable {
    var trainingDayId: String
    var checklist: [V1JournalAutoChecklistItem]

    init(trainingDayId: String = "", checklist: [V1JournalAutoChecklistItem] = []) {
        self.trainingDayId = trainingDayId
        self.checklist = checklist
    }

    private enum CodingKeys: String, CodingKey {
        case trainingDayId, checklist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trainingDayId = try container.decodeIfPresent(String.self, forKey: .trainingDayId) ?? ""
        // A line whose status the app does not know is dropped rather than failing the whole
        // checklist, as an unknown factor state is on the entry above.
        let lines = try container.decodeIfPresent([LenientLine].self, forKey: .checklist) ?? []
        checklist = lines.compactMap(\.item)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trainingDayId, forKey: .trainingDayId)
        try container.encode(checklist, forKey: .checklist)
    }

    /// Decodes a line without committing to its status, so one unknown value costs one line.
    private struct LenientLine: Decodable {
        let item: V1JournalAutoChecklistItem?

        private enum CodingKeys: String, CodingKey {
            case id, label, status, detail
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let id = try container.decode(String.self, forKey: .id)
            let label = try container.decode(String.self, forKey: .label)
            let rawStatus = try container.decode(String.self, forKey: .status)
            guard let status = JournalAutoStatus(rawValue: rawStatus) else {
                item = nil
                return
            }
            item = V1JournalAutoChecklistItem(
                id: id,
                label: label,
                status: status,
                detail: try container.decodeIfPresent(String.self, forKey: .detail)
            )
        }
    }
}

/// The nine checklist lines the web derives, in the order it renders them.
///
/// Named here as well as in the catalogue because the app has to know, before asking, whether
/// the athlete turned any of them on — an athlete who turned none on should not pay a request.
nonisolated enum JournalAutoItem {
    static let ids = [
        "steps_10k",
        "stress_ok",
        "nap",
        "cardio_20",
        "strength_20",
        "sleep_target",
        "body_battery_ok",
        "hydration_sync",
        "outdoor_minutes"
    ]
}

/// One trackable the athlete wrote themselves. Pro only, enforced by the server.
nonisolated struct JournalCustomItem: Identifiable, Equatable, Sendable {
    let id: String
    var label: String
    var enabled: Bool
}

/// The profile's journal preferences, kept as the JSON the server sent.
///
/// The web stores keys the app does not model — auto-checklist ids fed by device sync,
/// diet flags, analysis thresholds — and the server rebuilds the enable map from
/// defaults for every key a payload omits. Sending back only what the app renders
/// would therefore silently reset the rest, so the untouched keys travel along.
nonisolated struct JournalPrefs: Equatable, Sendable {
    private(set) var raw: [String: JSONValue]

    static let empty = JournalPrefs(raw: ["version": .number(2), "enabled": .object([:])])

    init(raw: [String: JSONValue]) {
        self.raw = raw
    }

    // MARK: Built-in trackables

    func isEnabled(_ id: String) -> Bool {
        enabledMap[id] == .bool(true)
    }

    mutating func setEnabled(_ id: String, _ enabled: Bool) {
        var map = enabledMap
        map[id] = .bool(enabled)
        raw["enabled"] = .object(map)
    }

    private var enabledMap: [String: JSONValue] {
        if case .object(let map)? = raw["enabled"] { map } else { [:] }
    }

    // MARK: Custom trackables

    var customItems: [JournalCustomItem] {
        guard case .array(let items)? = raw["customItems"] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"]?.string, let label = item["label"]?.string else { return nil }
            return JournalCustomItem(id: id, label: label, enabled: item["enabled"] == .bool(true))
        }
    }

    mutating func setCustomItems(_ items: [JournalCustomItem]) {
        raw["customItems"] = .array(
            items.map { item in
                .object([
                    "id": .string(item.id),
                    "label": .string(item.label),
                    "enabled": .bool(item.enabled)
                ])
            }
        )
    }

    // MARK: The automatic checklist

    /// Whether any derived line is turned on. False means the checklist section is absent,
    /// so the day-signals route is never called.
    var hasAnyAutoItem: Bool {
        JournalAutoItem.ids.contains { isEnabled($0) }
    }

    // MARK: Limits

    /// Free plans cap how many trackables run at once. Counts every enabled key, not
    /// only the ones the app renders, so the number matches what the web shows.
    static let freeEnabledLimit = 10

    var enabledCount: Int {
        let builtin = enabledMap.values.count { $0 == .bool(true) }
        return builtin + customItems.count { $0.enabled }
    }

    func canEnableAnother(isPro: Bool) -> Bool {
        isPro || enabledCount < Self.freeEnabledLimit
    }

    nonisolated static func makeCustomId() -> String {
        "custom_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased())"
    }
}

nonisolated struct V1JournalPrefsEnvelope: Decodable {
    let prefs: JSONValue?
    let isPro: Bool?
}
