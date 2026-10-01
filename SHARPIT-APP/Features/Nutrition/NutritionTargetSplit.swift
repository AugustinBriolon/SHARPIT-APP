import Foundation

/// The macros as shares of the energy target — the targets sheet's « % » mode, mirroring the
/// server: three whole percentages totalling exactly 100, each worth
/// `round(kcal × pct / 100 / kcalPerGram)` grams.
nonisolated struct NutritionTargetSplit: Equatable, Sendable {
    /// Kilocalories per gram (Atwater), the factors the server divides by.
    static let proteinKcalPerGram = 4.0
    static let carbsKcalPerGram = 4.0
    static let fatKcalPerGram = 9.0
    static let requiredTotal = 100

    /// Nil when empty or outside 800–8 000.
    var kcal: Int?
    var proteinPct: Int?
    var carbsPct: Int?
    var fatPct: Int?
    /// A share holds something other than a whole number from 0 to 100.
    var hasInvalidShare = false

    init(kcal: Int?, proteinPct: Int?, carbsPct: Int?, fatPct: Int?) {
        self.kcal = kcal
        self.proteinPct = proteinPct
        self.carbsPct = carbsPct
        self.fatPct = fatPct
    }

    /// The form as typed.
    init(kcal: String, protein: String, carbs: String, fat: String) {
        self.kcal = NutritionTargetsInput.requiredKcal(kcal)
        let shares = [protein, carbs, fat].map(Self.share)
        proteinPct = shares[0] ?? nil
        carbsPct = shares[1] ?? nil
        fatPct = shares[2] ?? nil
        hasInvalidShare = shares.contains { $0 == nil }
    }

    /// The shares typed so far, an empty one counting as zero, for the live total.
    var total: Int { (proteinPct ?? 0) + (carbsPct ?? 0) + (fatPct ?? 0) }

    var isBalanced: Bool { total == Self.requiredTotal }

    var proteinG: Int? { grams(proteinPct, kcalPerGram: Self.proteinKcalPerGram) }
    var carbsG: Int? { grams(carbsPct, kcalPerGram: Self.carbsKcalPerGram) }
    var fatG: Int? { grams(fatPct, kcalPerGram: Self.fatKcalPerGram) }

    /// What « OK » sends: only an energy in range and three shares totalling 100. The grams are
    /// the server's own arithmetic, so the screen shows them before the answer comes back.
    var targets: V1NutritionTargets? {
        guard let kcal, let proteinPct, let carbsPct, let fatPct, let proteinG, let carbsG, let fatG,
              !hasInvalidShare, isBalanced
        else { return nil }
        return V1NutritionTargets(
            mode: .percent, kcal: kcal,
            proteinG: Double(proteinG), carbsG: Double(carbsG), fatG: Double(fatG),
            proteinPct: proteinPct, carbsPct: carbsPct, fatPct: fatPct
        )
    }

    static func grams(kcal: Int, pct: Int, kcalPerGram: Double) -> Int {
        Int((Double(kcal) * Double(pct) / 100 / kcalPerGram).rounded())
    }

    /// The shares a set of grams makes of `kcal`, for switching from grams to « % ». Grams that
    /// add up to the energy (give or take rounding) are spread to exactly 100 by largest
    /// remainder; grams that do not are rounded one by one, so the total says they are off.
    static func shares(kcal: Int, proteinG: Double?, carbsG: Double?, fatG: Double?) -> NutritionTargetSplit {
        guard kcal > 0 else { return NutritionTargetSplit(kcal: nil, proteinPct: nil, carbsPct: nil, fatPct: nil) }
        let exact = [
            proteinG.map { $0 * proteinKcalPerGram * 100 / Double(kcal) },
            carbsG.map { $0 * carbsKcalPerGram * 100 / Double(kcal) },
            fatG.map { $0 * fatKcalPerGram * 100 / Double(kcal) },
        ]
        let complete = exact.compactMap { $0 }
        let rounded: [Int?]
        if complete.count == exact.count, abs(complete.reduce(0, +) - Double(requiredTotal)) <= 2 {
            rounded = largestRemainder(complete).map(Optional.some)
        } else {
            rounded = exact.map { $0.map { Int($0.rounded()) } }
        }
        return NutritionTargetSplit(kcal: kcal, proteinPct: rounded[0], carbsPct: rounded[1], fatPct: rounded[2])
    }

    /// What the « % » fields open on: the shares the server stored, else the ones the stored
    /// grams make of the energy, else nothing but the energy.
    static func prefill(from targets: V1NutritionTargets) -> NutritionTargetSplit {
        if let proteinPct = targets.proteinPct, let carbsPct = targets.carbsPct, let fatPct = targets.fatPct {
            return NutritionTargetSplit(kcal: targets.kcal, proteinPct: proteinPct, carbsPct: carbsPct, fatPct: fatPct)
        }
        guard let kcal = targets.kcal else {
            return NutritionTargetSplit(kcal: nil, proteinPct: nil, carbsPct: nil, fatPct: nil)
        }
        return shares(kcal: kcal, proteinG: targets.proteinG, carbsG: targets.carbsG, fatG: targets.fatG)
    }

    /// The grams form switched to « % »: the shares its grams make of its energy. Nil when the
    /// energy is not known yet or no macro is typed, so the « % » fields keep what they held.
    static func fromGramsForm(kcal: String, protein: String, carbs: String, fat: String) -> NutritionTargetSplit? {
        guard let kcalValue = NutritionTargetsInput.requiredKcal(kcal),
              let grams = NutritionTargetsInput.parse(kcal: kcal, protein: protein, carbs: carbs, fat: fat),
              grams.proteinG != nil || grams.carbsG != nil || grams.fatG != nil
        else { return nil }
        return shares(kcal: kcalValue, proteinG: grams.proteinG, carbsG: grams.carbsG, fatG: grams.fatG)
    }

    /// Whole shares totalling exactly 100, each as close as can be to its exact value.
    private static func largestRemainder(_ values: [Double]) -> [Int] {
        let sum = values.reduce(0, +)
        let scaled = values.map { $0 * Double(requiredTotal) / sum }
        var shares = scaled.map { Int($0.rounded(.down)) }
        let byRemainder = scaled.indices.sorted { scaled[$0] - Double(shares[$0]) > scaled[$1] - Double(shares[$1]) }
        for index in byRemainder.prefix(requiredTotal - shares.reduce(0, +)) {
            shares[index] += 1
        }
        return shares
    }

    private func grams(_ pct: Int?, kcalPerGram: Double) -> Int? {
        guard let kcal, let pct else { return nil }
        return Self.grams(kcal: kcal, pct: pct, kcalPerGram: kcalPerGram)
    }

    /// `.some(nil)` when empty, `.some(value)` for a whole number from 0 to 100, nil otherwise.
    private static func share(_ text: String) -> Int?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .some(nil) }
        guard let value = Int(trimmed), (0...requiredTotal).contains(value) else { return nil }
        return .some(value)
    }
}
