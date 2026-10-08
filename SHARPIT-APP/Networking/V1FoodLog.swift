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
    /// Live Sharpit score of the linked product, when known.
    var health: V1FoodHealth? = nil
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
    var saltPer100g: Double? = nil
    var saturatedFatPer100g: Double? = nil
    var servingGrams: Double?
    var servingLabel: String?
    /// Sharpit composition score when the server could compute one.
    var health: V1FoodHealth? = nil
    /// Values measured by ANSES (Ciqual), given by the manufacturer or checked on Open Food Facts
    /// (SHARPIT ADR-069). Absent from a server older than the badge.
    var verified: Bool? = nil
    /// `ciqual`, `producer` or `checked`.
    var verifiedBy: String? = nil
    /// Set on an own food made of other foods (SHARPIT ADR-071).
    var recipe: V1Recipe? = nil

    var isVerified: Bool { verified == true }
    var isRecipe: Bool { recipe != nil }

    /// Where verified values come from, as the badge says it to VoiceOver.
    var verifiedLabel: String? {
        guard isVerified else { return nil }
        switch verifiedBy {
        case "ciqual": return "Vérifié, valeurs mesurées par l'Anses"
        case "producer": return "Vérifié, données du fabricant"
        case "checked": return "Vérifié, fiche contrôlée par Open Food Facts"
        default: return "Vérifié"
        }
    }

    /// Open Food Facts data must carry its attribution wherever it is picked.
    var isOpenFoodFacts: Bool { source == "OFF" }
    /// A generic food from the ANSES Ciqual table (SHARPIT ADR-065).
    var isCiqual: Bool { source == "CIQUAL" }

    static let openFoodFactsAttribution = "Données Open Food Facts (ODbL)"
    static let ciqualAttribution = "Table Ciqual 2020, Anses (Licence Ouverte)"

    /// The attribution line the listed foods' sources ask for; nil for the athlete's own foods only.
    static func attribution(for products: [V1FoodProduct]) -> String? {
        var parts: [String] = []
        if products.contains(where: \.isCiqual) { parts.append(ciqualAttribution) }
        if products.contains(where: \.isOpenFoodFacts) { parts.append(openFoodFactsAttribution) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Sharpit food health score (server-computed, SHARPIT ADR-063): 0–100, what explains it
/// (highlights), the additives, and how the food fits the diets the athlete declared.
nonisolated struct V1FoodHealth: Codable, Sendable, Equatable, Hashable {
    var score: Int?
    var scoreVersion: Int
    var grade: Grade?
    var coverage: Coverage
    var nutriScore: String?
    /// The letter was computed from the label, not read from Open Food Facts.
    var nutriScoreEstimated: Bool = false
    var nova: Int?
    var nutrientFlags: NutrientFlags
    var additives: [Additive]
    var additivesKnown: AdditivesKnown = .list
    var additiveCount: Int? = nil
    var highlights: [Highlight] = []
    var dietFit: [DietFit] = []
    /// `summary` comes from a search hit: the product read by barcode completes it.
    var detail: Detail = .full

    enum Grade: String, Codable, Sendable, Equatable, Hashable {
        case excellent, good, mediocre, poor

        var label: String {
            switch self {
            case .excellent: "Excellent"
            case .good: "Correct"
            case .mediocre: "Médiocre"
            case .poor: "À éviter"
            }
        }
    }

    enum Coverage: String, Codable, Sendable, Equatable, Hashable {
        case full, partial, none
    }

    enum NutrientLevel: String, Codable, Sendable, Equatable, Hashable {
        case low, moderate, high, unknown

        var label: String {
            switch self {
            case .low: "Faible"
            case .moderate: "Modéré"
            case .high: "Élevé"
            case .unknown: "—"
            }
        }
    }

    enum AdditiveRisk: String, Codable, Sendable, Equatable, Hashable {
        case none, limited, high

        var label: String {
            switch self {
            case .none: "Sans risque"
            case .limited: "Risque limité"
            case .high: "À risque"
            }
        }
    }

    enum AdditivesKnown: String, Codable, Sendable, Equatable, Hashable {
        case list, count, unknown
    }

    enum Detail: String, Codable, Sendable, Equatable, Hashable {
        case summary, full
    }

    struct NutrientFlags: Codable, Sendable, Equatable, Hashable {
        var sugars: NutrientLevel
        var salt: NutrientLevel
        var saturatedFat: NutrientLevel
    }

    struct Additive: Codable, Sendable, Equatable, Hashable, Identifiable {
        var code: String
        var name: String
        var risk: AdditiveRisk
        var id: String { code }
    }

    /// One reason behind the score, worded by the server.
    struct Highlight: Codable, Sendable, Equatable, Hashable, Identifiable {
        enum Tone: String, Codable, Sendable, Equatable, Hashable {
            case negative, positive, neutral
        }

        var key: String
        var tone: Tone
        var label: String
        var detail: String?
        var id: String { key }
    }

    /// How the food reads against one declared diet.
    struct DietFit: Codable, Sendable, Equatable, Hashable, Identifiable {
        enum Status: String, Codable, Sendable, Equatable, Hashable {
            case compatible, uncertain, incompatible
        }

        var diet: String
        var label: String
        var status: Status
        var reason: String
        var id: String { diet }
    }

    var watchPoints: [Highlight] { highlights.filter { $0.tone == .negative } }
    var strengths: [Highlight] { highlights.filter { $0.tone == .positive } }
    var notes: [Highlight] { highlights.filter { $0.tone == .neutral } }
    var incompatibleDiets: [DietFit] { dietFit.filter { $0.status == .incompatible } }

    enum CodingKeys: String, CodingKey {
        case score, scoreVersion, grade, coverage, nutriScore, nutriScoreEstimated, nova, nutrientFlags
        case additives, additivesKnown, additiveCount, highlights, dietFit, detail
    }

    init(
        score: Int?, scoreVersion: Int, grade: Grade?, coverage: Coverage, nutriScore: String?,
        nutriScoreEstimated: Bool = false, nova: Int?, nutrientFlags: NutrientFlags, additives: [Additive],
        additivesKnown: AdditivesKnown = .list, additiveCount: Int? = nil, highlights: [Highlight] = [],
        dietFit: [DietFit] = [], detail: Detail = .full
    ) {
        self.score = score
        self.scoreVersion = scoreVersion
        self.grade = grade
        self.coverage = coverage
        self.nutriScore = nutriScore
        self.nutriScoreEstimated = nutriScoreEstimated
        self.nova = nova
        self.nutrientFlags = nutrientFlags
        self.additives = additives
        self.additivesKnown = additivesKnown
        self.additiveCount = additiveCount
        self.highlights = highlights
        self.dietFit = dietFit
        self.detail = detail
    }

    /// A score stored before version 2 (or kept in the read cache) has none of the explaining
    /// fields: it still reads, with nothing to explain.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decodeIfPresent(Int.self, forKey: .score)
        scoreVersion = try container.decode(Int.self, forKey: .scoreVersion)
        grade = try container.decodeIfPresent(Grade.self, forKey: .grade)
        coverage = try container.decode(Coverage.self, forKey: .coverage)
        nutriScore = try container.decodeIfPresent(String.self, forKey: .nutriScore)
        nutriScoreEstimated = try container.decodeIfPresent(Bool.self, forKey: .nutriScoreEstimated) ?? false
        nova = try container.decodeIfPresent(Int.self, forKey: .nova)
        nutrientFlags = try container.decode(NutrientFlags.self, forKey: .nutrientFlags)
        additives = try container.decodeIfPresent([Additive].self, forKey: .additives) ?? []
        additivesKnown = (try? container.decodeIfPresent(AdditivesKnown.self, forKey: .additivesKnown)) ?? .list
        additiveCount = try container.decodeIfPresent(Int.self, forKey: .additiveCount)
        highlights = (try? container.decodeIfPresent([Highlight].self, forKey: .highlights)) ?? []
        dietFit = (try? container.decodeIfPresent([DietFit].self, forKey: .dietFit)) ?? []
        detail = (try? container.decodeIfPresent(Detail.self, forKey: .detail)) ?? .full
    }
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

/// The score of a meal or a day, from the energy of its foods (SHARPIT ADR-070). Worded and
/// computed by the server; the app renders it.
nonisolated struct V1MealHealth: Codable, Sendable, Equatable, Hashable {
    /// Nil while less than half of the energy comes from scored foods.
    var score: Int?
    var grade: V1FoodHealth.Grade?
    /// Share of the energy whose food carries a score, 0–1.
    var coverage: Double
    var kcal: Double
    var protein: Double
    var fiber: Double?
    var ultraProcessedShare: Double?
    var highlights: [V1FoodHealth.Highlight]
}

/// Each meal's score and the day's, as `/api/v1/food-log` serves them.
nonisolated struct V1FoodLogDayHealth: Codable, Sendable, Equatable, Hashable {
    var day: V1MealHealth?
    /// Keyed by `FoodLogMeal.rawValue`; an empty meal reads null.
    var meals: [String: V1MealHealth?]

    func meal(_ meal: FoodLogMeal) -> V1MealHealth? {
        meals[meal.rawValue] ?? nil
    }
}

/// `GET /api/v1/food-log?trainingDayId=`.
nonisolated struct V1FoodLogDay: Decodable, Sendable, Equatable {
    let trainingDayId: String
    let entries: [V1FoodLogEntry]
    /// Absent from a server older than SHARPIT ADR-070.
    let health: V1FoodLogDayHealth?
    let targets: V1NutritionTargets
    let recent: [V1FoodLogRecentFood]

    enum CodingKeys: String, CodingKey { case trainingDayId, entries, health, targets, recent }

    init(
        trainingDayId: String,
        entries: [V1FoodLogEntry],
        health: V1FoodLogDayHealth? = nil,
        targets: V1NutritionTargets = .none,
        recent: [V1FoodLogRecentFood] = []
    ) {
        self.trainingDayId = trainingDayId
        self.entries = entries
        self.health = health
        self.targets = targets
        self.recent = recent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trainingDayId = try container.decode(String.self, forKey: .trainingDayId)
        entries = try container.decode([V1FoodLogEntry].self, forKey: .entries)
        health = try container.decodeIfPresent(V1FoodLogDayHealth.self, forKey: .health)
        targets = try container.decodeIfPresent(V1NutritionTargets.self, forKey: .targets) ?? .none
        recent = try container.decodeIfPresent([V1FoodLogRecentFood].self, forKey: .recent) ?? []
    }
}

/// A food the athlete logged in the last 90 days that matches the search (SHARPIT ADR-069).
nonisolated struct V1FoodEatenFood: Codable, Sendable, Equatable, Hashable {
    let product: V1FoodProduct
    let timesEaten: Int
    let lastGrams: Double
}

/// `GET /api/v1/food-log/foods?q=` — the foods already eaten, the athlete's own foods, generic
/// foods, then Open Food Facts.
nonisolated struct V1FoodSearchResults: Decodable, Sendable, Equatable {
    /// Listed first, and not repeated in the lists below.
    let eaten: [V1FoodEatenFood]
    let own: [V1FoodProduct]
    /// Generic foods from Ciqual (« Banane, pulpe, crue »), answered even when OFF is down.
    let generic: [V1FoodProduct]
    let products: [V1FoodProduct]
    /// Open Food Facts did not answer: only the athlete's own and generic foods are listed.
    let offUnavailable: Bool

    var isEmpty: Bool { eaten.isEmpty && own.isEmpty && generic.isEmpty && products.isEmpty }

    enum CodingKeys: String, CodingKey { case eaten, own, generic, products, offUnavailable }

    init(
        eaten: [V1FoodEatenFood] = [],
        own: [V1FoodProduct],
        generic: [V1FoodProduct] = [],
        products: [V1FoodProduct],
        offUnavailable: Bool
    ) {
        self.eaten = eaten
        self.own = own
        self.generic = generic
        self.products = products
        self.offUnavailable = offUnavailable
    }

    /// A server older than Ciqual sends no `generic`, one older than ADR-069 no `eaten`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eaten = try container.decodeIfPresent([V1FoodEatenFood].self, forKey: .eaten) ?? []
        own = try container.decode([V1FoodProduct].self, forKey: .own)
        generic = try container.decodeIfPresent([V1FoodProduct].self, forKey: .generic) ?? []
        products = try container.decode([V1FoodProduct].self, forKey: .products)
        offUnavailable = try container.decode(Bool.self, forKey: .offUnavailable)
    }
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

/// Typed in by hand: a name and its energy, macros optional.
nonisolated struct FoodQuickAdd: Sendable, Equatable, Hashable {
    var name: String
    var kcal: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
}

/// One food line from `POST /api/v1/food-log/describe` (portion macros + per-100 g for edits).
nonisolated struct V1DescribedFood: Decodable, Sendable, Equatable, Identifiable {
    var id: String { "\(name)-\(grams)" }
    let name: String
    let grams: Double
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let per100g: V1DescribedFoodPer100g
}

nonisolated struct V1DescribedFoodPer100g: Decodable, Sendable, Equatable {
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

nonisolated struct V1DescribedFoodList: Decodable, Sendable, Equatable {
    let items: [V1DescribedFood]
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
    var saltPer100g: Double? = nil
    var saturatedFatPer100g: Double? = nil
    var servingGrams: Double?
}
