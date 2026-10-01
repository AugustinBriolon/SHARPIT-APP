import Foundation

/// `/api/v1/food-log` — the in-app food log (SHARPIT ADR-061). Entries are what the athlete
/// writes; every write rebuilds the day server-side, so `/api/v1/nutrition` stays the one place
/// the day's totals, goals and reading are read from.

/// The four meals of a day, in the order the day is read. The raw value is the server's key.
nonisolated enum FoodLogMeal: String, CaseIterable, Codable, Sendable, Identifiable {
    case breakfast = "BREAKFAST"
    case lunch = "LUNCH"
    case dinner = "DINNER"
    case snacks = "SNACKS"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Petit-déjeuner"
        case .lunch: "Déjeuner"
        case .dinner: "Dîner"
        case .snacks: "Collations"
        }
    }

    /// The name `/api/v1/nutrition` gives the meal (`DailyNutrition.meals[].name`), which the
    /// meal symbols and the coach's flags are keyed by.
    var storedName: String { rawValue.lowercased() }

    /// The meal a new entry most likely belongs to at this time of day.
    static func suggested(at date: Date, calendar: Calendar = .current) -> FoodLogMeal {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 12) * 60 + (parts.minute ?? 0)
        switch minutes {
        case ..<(10 * 60 + 30): return .breakfast
        case ..<(15 * 60): return .lunch
        case ..<(18 * 60): return .snacks
        default: return .dinner
        }
    }

    /// A meal key this app does not know yet reads as a snack rather than costing the day.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FoodLogMeal(rawValue: raw.uppercased()) ?? .snacks
    }
}

/// One logged food: the portion and the nutrients snapshotted when it was logged.
nonisolated struct V1FoodLogEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
    let id: String
    var meal: FoodLogMeal
    var productId: String?
    var name: String
    var brand: String?
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?
    var createdAt: String?
}

/// A food the athlete can log: an Open Food Facts product cached by the server, or their own.
nonisolated struct V1FoodProduct: Codable, Sendable, Equatable, Hashable, Identifiable {
    let id: String
    /// `OFF` or `CUSTOM`.
    var source: String
    var barcode: String?
    var name: String
    var brand: String?
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double?
    var sugarPer100g: Double?
    var servingGrams: Double?
    var servingLabel: String?

    /// Open Food Facts data must carry its attribution wherever it is picked.
    var isOpenFoodFacts: Bool { source == "OFF" }
}

/// How the athlete sets their macros: in grams, or as shares of the energy target.
nonisolated enum NutritionTargetsMode: String, Codable, Sendable, CaseIterable {
    case grams = "GRAMS"
    case percent = "PERCENT"

    /// A mode this app does not know yet reads as grams, which the server always fills.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NutritionTargetsMode(rawValue: raw.uppercased()) ?? .grams
    }
}

/// The athlete's own daily targets. Nil means not set. The grams are always filled, also in
/// `percent` mode, where the server derives them from the energy and the three shares.
nonisolated struct V1NutritionTargets: Codable, Sendable, Equatable {
    var mode: NutritionTargetsMode
    var kcal: Int?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    /// Set only in `percent` mode.
    var proteinPct: Int?
    var carbsPct: Int?
    var fatPct: Int?

    static let none = V1NutritionTargets(kcal: nil, proteinG: nil, carbsG: nil, fatG: nil)

    enum CodingKeys: String, CodingKey {
        case mode, kcal, proteinG, carbsG, fatG, proteinPct, carbsPct, fatPct
    }

    /// A whole number may arrive as `2400.0`, and a server older than the percent mode sends
    /// neither `mode` nor the shares: both must still read.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? container.decodeIfPresent(NutritionTargetsMode.self, forKey: .mode)) ?? .grams
        kcal = try Self.wholeNumber(container, .kcal)
        proteinG = try container.decodeIfPresent(Double.self, forKey: .proteinG)
        carbsG = try container.decodeIfPresent(Double.self, forKey: .carbsG)
        fatG = try container.decodeIfPresent(Double.self, forKey: .fatG)
        proteinPct = try Self.wholeNumber(container, .proteinPct)
        carbsPct = try Self.wholeNumber(container, .carbsPct)
        fatPct = try Self.wholeNumber(container, .fatPct)
    }

    init(
        mode: NutritionTargetsMode = .grams,
        kcal: Int?,
        proteinG: Double?,
        carbsG: Double?,
        fatG: Double?,
        proteinPct: Int? = nil,
        carbsPct: Int? = nil,
        fatPct: Int? = nil
    ) {
        self.mode = mode
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.proteinPct = proteinPct
        self.carbsPct = carbsPct
        self.fatPct = fatPct
    }

    private static func wholeNumber(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Int? {
        if let whole = try? container.decodeIfPresent(Int.self, forKey: key) { return whole }
        return try container.decodeIfPresent(Double.self, forKey: key).map { Int($0.rounded()) }
    }
}

nonisolated struct V1FoodLogRecentFood: Codable, Sendable, Equatable, Hashable {
    let product: V1FoodProduct
    let lastGrams: Double
}

/// `GET /api/v1/food-log?trainingDayId=`.
nonisolated struct V1FoodLogDay: Decodable, Sendable, Equatable {
    let trainingDayId: String
    let entries: [V1FoodLogEntry]
    let targets: V1NutritionTargets
    let recent: [V1FoodLogRecentFood]

    enum CodingKeys: String, CodingKey { case trainingDayId, entries, targets, recent }

    init(trainingDayId: String, entries: [V1FoodLogEntry], targets: V1NutritionTargets = .none, recent: [V1FoodLogRecentFood] = []) {
        self.trainingDayId = trainingDayId
        self.entries = entries
        self.targets = targets
        self.recent = recent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trainingDayId = try container.decode(String.self, forKey: .trainingDayId)
        entries = try container.decode([V1FoodLogEntry].self, forKey: .entries)
        targets = try container.decodeIfPresent(V1NutritionTargets.self, forKey: .targets) ?? .none
        recent = try container.decodeIfPresent([V1FoodLogRecentFood].self, forKey: .recent) ?? []
    }
}

/// `GET /api/v1/food-log/foods?q=` — the athlete's own foods first, then Open Food Facts.
nonisolated struct V1FoodSearchResults: Decodable, Sendable, Equatable {
    let own: [V1FoodProduct]
    let products: [V1FoodProduct]
    /// Open Food Facts did not answer: only the athlete's own foods are listed.
    let offUnavailable: Bool

    var isEmpty: Bool { own.isEmpty && products.isEmpty }
}

nonisolated struct V1FoodLogEntryEnvelope: Decodable, Sendable {
    let entry: V1FoodLogEntry
}

nonisolated struct V1FoodProductEnvelope: Decodable, Sendable {
    let product: V1FoodProduct
}

nonisolated struct V1NutritionTargetsEnvelope: Decodable, Sendable {
    let targets: V1NutritionTargets
}

/// `GET /api/v1/food-log/foods/mine` — the athlete's own foods.
nonisolated struct V1FoodProductList: Decodable, Sendable, Equatable {
    let foods: [V1FoodProduct]
}

/// `POST /api/v1/food-log/import/myfitnesspal` — what the athlete's MyFitnessPal export brought:
/// one day per date with meals in it, each meal as its total.
nonisolated struct V1FoodLogImportResult: Decodable, Sendable, Equatable {
    let importedDays: Int
    /// `YYYY-MM-DD`; nil when nothing was imported.
    let firstDay: String?
    let lastDay: String?
    /// Lines of the file the server could not read.
    let skippedRows: Int

    enum CodingKeys: String, CodingKey { case importedDays, firstDay, lastDay, skippedRows }

    init(importedDays: Int, firstDay: String?, lastDay: String?, skippedRows: Int = 0) {
        self.importedDays = importedDays
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.skippedRows = skippedRows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        importedDays = try container.decode(Int.self, forKey: .importedDays)
        firstDay = try container.decodeIfPresent(String.self, forKey: .firstDay)
        lastDay = try container.decodeIfPresent(String.self, forKey: .lastDay)
        skippedRows = try container.decodeIfPresent(Int.self, forKey: .skippedRows) ?? 0
    }
}

/// Typed in by hand: a name and its energy, macros optional.
nonisolated struct FoodQuickAdd: Sendable, Equatable, Hashable {
    var name: String
    var kcal: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
}

/// What a new entry is made of: a known food (scanned, searched, own) or a quick add.
nonisolated enum FoodLogEntrySource: Sendable, Equatable, Hashable {
    case product(V1FoodProduct)
    case quick(FoodQuickAdd)
}

/// A new entry, before the server has given it an id.
nonisolated struct FoodLogDraft: Sendable, Equatable {
    var trainingDayId: String
    var meal: FoodLogMeal
    var grams: Double
    var source: FoodLogEntrySource
}

/// A new portion or a new meal for an entry. Nil leaves the field as it is.
nonisolated struct FoodLogEntryChange: Sendable, Equatable {
    var grams: Double?
    var meal: FoodLogMeal?
}

/// The athlete's own food, per 100 g.
nonisolated struct FoodCustomDraft: Sendable, Equatable {
    var name: String
    var brand: String?
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double?
    var sugarPer100g: Double?
    var servingGrams: Double?
}
