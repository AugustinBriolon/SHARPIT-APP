import SwiftUI

/// A food's energy split by macro on one thin bar, in the macros' hues: what it is made of,
/// read before its figures. Nothing is drawn for a food without energy.
struct NutritionMacroSplitBar: View {
    let protein: Double
    let carbohydrates: Double
    let fat: Double
    var height: CGFloat = 4

    private var split: [(macro: NutritionReadout.Macro, share: Double)] {
        NutritionReadout.energySplit(protein: protein, carbohydrates: carbohydrates, fat: fat)
    }

    var body: some View {
        let parts = split
        if !parts.isEmpty {
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    ForEach(parts.filter { $0.share > 0 }, id: \.macro) { part in
                        Capsule()
                            .fill(part.macro.tone)
                            .frame(width: max(geo.size.width * part.share - 1.5, 2))
                    }
                }
            }
            .frame(height: height)
            .clipShape(Capsule())
            .accessibilityElement()
            .accessibilityLabel(accessibilityText(parts))
        }
    }

    private func accessibilityText(_ parts: [(macro: NutritionReadout.Macro, share: Double)]) -> String {
        parts.map { "\($0.macro.label) \(Int(($0.share * 100).rounded())) %" }.joined(separator: ", ")
    }
}

extension NutritionMacroSplitBar {
    init(product: V1FoodProduct, height: CGFloat = 4) {
        self.init(protein: product.proteinPer100g, carbohydrates: product.carbsPer100g, fat: product.fatPer100g, height: height)
    }

    init(entry: V1FoodLogEntry, height: CGFloat = 4) {
        self.init(protein: entry.protein, carbohydrates: entry.carbs, fat: entry.fat, height: height)
    }
}
