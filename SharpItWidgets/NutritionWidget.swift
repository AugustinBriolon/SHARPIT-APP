import SwiftUI
import WidgetKit

/// « Nutrition »: what is left to eat today on the energy dial, and the three macros against
/// their goals — the server's goal and remainder, never recomputed.
struct NutritionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Nutrition", provider: SnapshotProvider()) { entry in
            NutritionWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(entry.nutrition?.isConnected == false ? WidgetSnapshot.link("/settings/sources") : WidgetSnapshot.link("/today"))
        }
        .configurationDisplayName("Nutrition")
        .description("Tes calories restantes et tes macros du jour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct NutritionWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.features.isOn(.nutrition) {
            content
        } else {
            WidgetFeatureOff(feature: .nutrition)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: NutritionCircular(nutrition: entry.nutrition)
        case .accessoryRectangular: NutritionRectangular(nutrition: entry.nutrition)
        case .systemMedium: NutritionMedium(nutrition: entry.nutrition)
        default: NutritionSmall(nutrition: entry.nutrition)
        }
    }
}

/// Before a log: what to do, never an empty dial pretending to read.
private struct NutritionAwaiting: View {
    let nutrition: WidgetSnapshot.Nutrition?

    var body: some View {
        WidgetFrame("Nutrition", symbol: "fork.knife") {
            WidgetAwaitingData(text: message)
        }
    }

    private var message: String {
        guard let nutrition else { return "Ouvre SharpIt pour charger ta journée." }
        if !nutrition.isConnected { return "Relie MyFitnessPal pour suivre tes calories." }
        return "Rien de noté aujourd'hui."
    }
}

struct NutritionSmall: View {
    let nutrition: WidgetSnapshot.Nutrition?

    var body: some View {
        if let nutrition, nutrition.hasLog {
            WidgetFrame("Nutrition", symbol: "fork.knife") {
                DialReadout(score: nutrition.dialScore, figure: nutrition.dialFigure)
                WidgetCaption(text: nutrition.dialCaption)
                    .frame(maxWidth: .infinity)
            }
        } else {
            NutritionAwaiting(nutrition: nutrition)
        }
    }
}

struct NutritionMedium: View {
    let nutrition: WidgetSnapshot.Nutrition?

    var body: some View {
        if let nutrition, nutrition.hasLog {
            WidgetFrame("Nutrition", symbol: "fork.knife") {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(spacing: 2) {
                        DialReadout(score: nutrition.dialScore, figure: nutrition.dialFigure)
                        WidgetCaption(text: nutrition.dialCaption)
                    }
                    .frame(width: 118)
                    VStack(alignment: .leading, spacing: 7) {
                        WidgetCaption(text: "\(SharpitFigureFormat.kcal(nutrition.calories)) / \(SharpitFigureFormat.kcal(nutrition.calorieGoal)) kcal")
                        ForEach(nutrition.macros) { MacroLine(macro: $0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            NutritionAwaiting(nutrition: nutrition)
        }
    }
}

/// One macro: its name, its grams against the goal, a bar in its hue.
private struct MacroLine: View {
    let macro: WidgetSnapshot.Macro

    private var fill: Double {
        guard let goal = macro.goalGrams, goal > 0 else { return 0 }
        return min(macro.grams / goal, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(macro.kind.label)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 4)
                Text(macro.goalGrams.map { "\(Int(macro.grams.rounded())) / \(Int($0.rounded())) g" } ?? "\(Int(macro.grams.rounded())) g")
                    .font(SharpitTypography.meta.monospacedDigit())
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SharpitColor.analysisBorder)
                    Capsule().fill(macro.kind.tone).frame(width: proxy.size.width * fill)
                }
            }
            .frame(height: 4)
            .widgetAccentable()
        }
    }
}

struct NutritionCircular: View {
    let nutrition: WidgetSnapshot.Nutrition?

    var body: some View {
        if let nutrition, nutrition.hasLog {
            Gauge(value: Double(nutrition.dialScore ?? 0), in: 0...100) {
                Image(systemName: "fork.knife")
            } currentValueLabel: {
                Text(nutrition.dialFigure).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "fork.knife").font(.title3)
            }
        }
    }
}

struct NutritionRectangular: View {
    let nutrition: WidgetSnapshot.Nutrition?

    var body: some View {
        if let nutrition, nutrition.hasLog {
            VStack(alignment: .leading, spacing: 1) {
                Label("\(nutrition.dialFigure) \(nutrition.dialCaption)", systemImage: "fork.knife")
                    .font(.headline)
                    .widgetAccentable()
                Text(nutrition.macros.map { "\($0.kind.label.prefix(1)) \(Int($0.grams.rounded()))" }.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label(nutrition?.isConnected == false ? "Relie MyFitnessPal" : "Rien de noté", systemImage: "fork.knife")
                .font(.headline)
        }
    }
}
