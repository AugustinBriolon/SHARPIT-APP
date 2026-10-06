import Foundation

/// A reference the web's estimator can revise from the records, and the athlete can accept
/// one by one (`ThresholdField` in the web's `threshold-estimates.ts`).
nonisolated enum V1ThresholdField: String, Codable, CaseIterable, Sendable {
    case ftpW
    case runThresholdPaceSecPerKm
    case swimCssSecPer100m
}

/// Which way a proposal moves the reference, in performance terms: a faster pace is `up`.
nonisolated enum V1ThresholdDirection: String, Sendable {
    case up
    case down
    case set
}

/// `GET /api/v1/athlete-profile/apply-estimates` — what the records say the thresholds are,
/// beside what the profile holds. The server decides what is worth proposing (recency window,
/// materiality) and words both sides; the app shows them as they come.
nonisolated struct V1ThresholdApplyPreview: Decodable, Sendable, Equatable {
    let estimates: V1ThresholdEstimates
    let changes: [V1ThresholdChange]

    init(estimates: V1ThresholdEstimates = V1ThresholdEstimates(), changes: [V1ThresholdChange] = []) {
        self.estimates = estimates
        self.changes = changes
    }

    private enum CodingKeys: String, CodingKey { case estimates, changes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        estimates = (try? container.decodeIfPresent(V1ThresholdEstimates.self, forKey: .estimates)) ?? V1ThresholdEstimates()
        // A field this build does not know is dropped rather than failing the whole proposal.
        changes = (try? container.decodeIfPresent(LossyRecordArray<V1ThresholdChange>.self, forKey: .changes))?.items ?? []
    }

    var hasChanges: Bool { !changes.isEmpty }

    /// The proposal without the fields just applied.
    func removing(_ fields: Set<V1ThresholdField>) -> V1ThresholdApplyPreview {
        V1ThresholdApplyPreview(estimates: estimates, changes: changes.filter { !fields.contains($0.field) })
    }

    /// The profile change the server will make for `fields`, so the screen shows it on the tap.
    func patch(for fields: Set<V1ThresholdField>) -> AthleteProfilePatch {
        var patch = AthleteProfilePatch()
        let offered = Set(changes.map(\.field))
        for field in V1ThresholdField.allCases where fields.contains(field) && offered.contains(field) {
            switch field {
            case .ftpW:
                if let ftp = estimates.ftpW { patch.set(.ftpW, int: Int(ftp.rounded())) }
            case .runThresholdPaceSecPerKm:
                if let pace = estimates.runThresholdPaceSecPerKm { patch.set(.runThresholdPaceSecPerKm, double: pace) }
            case .swimCssSecPer100m:
                if let css = estimates.swimCssSecPer100m { patch.set(.swimCssSecPer100m, double: css) }
            }
        }
        return patch
    }
}

nonisolated struct V1ThresholdEstimates: Decodable, Sendable, Equatable {
    var ftpW: Double?
    var runThresholdPaceSecPerKm: Double?
    var swimCssSecPer100m: Double?
    /// Days of history the estimate could see — « Capacité démontrée sur 120 jours ».
    var windowDays: Int?

    init(
        ftpW: Double? = nil,
        runThresholdPaceSecPerKm: Double? = nil,
        swimCssSecPer100m: Double? = nil,
        windowDays: Int? = nil
    ) {
        self.ftpW = ftpW
        self.runThresholdPaceSecPerKm = runThresholdPaceSecPerKm
        self.swimCssSecPer100m = swimCssSecPer100m
        self.windowDays = windowDays
    }
}

/// One proposal: « FTP vélo · 250 W → 265 W ».
nonisolated struct V1ThresholdChange: Decodable, Sendable, Equatable, Identifiable {
    let field: V1ThresholdField
    let label: String
    let from: String
    let to: String
    let direction: V1ThresholdDirection

    var id: String { field.rawValue }

    init(field: V1ThresholdField, label: String, from: String, to: String, direction: V1ThresholdDirection) {
        self.field = field
        self.label = label
        self.from = from
        self.to = to
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey { case field, label, from, to, direction }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        field = try container.decode(V1ThresholdField.self, forKey: .field)
        label = try container.decode(String.self, forKey: .label)
        from = (try? container.decodeIfPresent(String.self, forKey: .from)) ?? "—"
        to = try container.decode(String.self, forKey: .to)
        let raw = try? container.decodeIfPresent(String.self, forKey: .direction)
        direction = raw.flatMap(V1ThresholdDirection.init(rawValue:)) ?? .set
    }
}

/// Why `POST /apply-estimates` wrote nothing: the server answers 400 with the reason.
nonisolated enum V1ThresholdApplyRefusal: String, Sendable {
    case noEstimates = "no_estimates"
    case unchanged
    case nothingSelected = "nothing_selected"

    var message: String {
        switch self {
        case .noEstimates: "Pas assez de séances récentes pour estimer tes seuils."
        case .unchanged: "Tes seuils sont déjà à jour."
        case .nothingSelected: "Aucune proposition retenue."
        }
    }
}

/// `POST /api/v1/athlete-profile/import-garmin` — what Garmin gave, already written to the
/// profile by the server (only the fields Garmin returned).
nonisolated struct V1GarminThresholdImport: Decodable, Sendable, Equatable {
    var imported: Bool
    var ftpW: Double?
    var maxHr: Double?
    var lthr: Double?
    var runThresholdPaceSecPerKm: Double?
    var vo2maxRunning: Double?
    var vo2maxCycling: Double?
    /// Garmin endpoints that did not answer: their fields are unknown, not absent.
    var failedSources: [String]

    init(imported: Bool, failedSources: [String] = []) {
        self.imported = imported
        self.failedSources = failedSources
    }

    private enum CodingKeys: String, CodingKey {
        case imported, ftpW, maxHr, lthr, runThresholdPaceSecPerKm, vo2maxRunning, vo2maxCycling, failedSources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imported = (try? container.decodeIfPresent(Bool.self, forKey: .imported)) ?? false
        ftpW = try? container.decodeIfPresent(Double.self, forKey: .ftpW)
        maxHr = try? container.decodeIfPresent(Double.self, forKey: .maxHr)
        lthr = try? container.decodeIfPresent(Double.self, forKey: .lthr)
        runThresholdPaceSecPerKm = try? container.decodeIfPresent(Double.self, forKey: .runThresholdPaceSecPerKm)
        vo2maxRunning = try? container.decodeIfPresent(Double.self, forKey: .vo2maxRunning)
        vo2maxCycling = try? container.decodeIfPresent(Double.self, forKey: .vo2maxCycling)
        failedSources = (try? container.decodeIfPresent([String].self, forKey: .failedSources)) ?? []
    }

    /// The line under the button, in the web's words (`buildGarminImportMessage`).
    var message: String {
        let failed = failedSources.map(Self.sourceLabel).joined(separator: ", ")
        if !imported {
            if !failedSources.isEmpty {
                return "Garmin n'a pas répondu pour : \(failed). Ces seuils sont inconnus, pas absents : réessaie."
            }
            return "Aucun seuil trouvé sur ton compte Garmin."
        }
        if !failedSources.isEmpty {
            return "Import partiel : Garmin n'a pas répondu pour \(failed)."
        }
        return "Seuils importés depuis Garmin et enregistrés."
    }

    static func sourceLabel(_ source: String) -> String {
        switch source {
        case "user-settings": "réglages athlète"
        case "heart-rate-zones": "zones de FC"
        case "power-zones": "zones de puissance"
        default: source
        }
    }
}

/// The estimates and the Garmin import, beside the profile they write to.
nonisolated protocol ThresholdEstimating: Sendable {
    func thresholdPreview(token: String) async throws -> V1ThresholdApplyPreview
    /// Writes the accepted estimates; the server re-checks them against its own proposal.
    func applyThresholdEstimates(fields: [V1ThresholdField], token: String) async throws
    func importGarminThresholds(token: String) async throws -> V1GarminThresholdImport
}
