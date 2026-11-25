import SwiftUI
import WidgetKit

/// « Résumé »: the day's four rings as the app's first screen draws them — last night, the
/// recovery, the day's food, the week's regularity — two by two with their glyphs on the small widget, side by
/// side with their names on the medium one. A ring the athlete hides in the app is left out.
struct ResumeRingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ResumeRings", provider: SnapshotProvider()) { entry in
            ResumeRingsView(entry: entry)
                .sharpitWidgetChrome()
                .widgetURL(entry.link("/today"))
        }
        .configurationDisplayName("Résumé")
        .description("Tes anneaux du jour : sommeil, récupération, nutrition, régularité.")
        // On the Lock Screen it is the morning's verdict that is read, with the night and the
        // recovery under it: the call the athlete wakes up to, without opening the app.
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct ResumeRingsView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var rings: [WidgetResumeRing] {
        WidgetResumeRing.rings(day: entry.day, nutrition: entry.nutrition, regularity: entry.regularity, features: entry.features)
    }

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                lockScreenRectangular
            } else if family == .accessoryInline {
                lockScreenInline
            } else if entry.day == nil {
                WidgetAwaitingDay(eyebrow: String(localized: "Résumé"), symbol: "circle.hexagongrid")
            } else if family == .systemMedium {
                WidgetFrame(String(localized: "Résumé"), symbol: "circle.hexagongrid") {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(rings) { ring in
                            column(ring).frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: rings.count, by: 2)), id: \.self) { start in
                        GridRow {
                            ForEach(rings[start..<min(start + 2, rings.count)]) { ring in
                                cell(ring)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Health values: redacted on a locked device.
        .privacySensitive()
    }

    // MARK: Lock Screen

    /// The verdict's posture word over its headline, the night and the recovery under it.
    @ViewBuilder
    private var lockScreenRectangular: some View {
        if let day = entry.day, let verdict = day.verdict {
            VStack(alignment: .leading, spacing: 1) {
                Label(verdict.status, systemImage: "circle.hexagongrid")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(verdict.headline)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let line = WidgetResumeRing.lockScreenLine(day: day) {
                    Text(line).font(.caption.monospacedDigit()).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Label(
                entry.day == nil ? String(localized: "Ouvre SharpIt") : String(localized: "Verdict en attente de ta nuit"),
                systemImage: "circle.hexagongrid"
            )
            .font(.headline)
            .lineLimit(2)
        }
    }

    /// One line above the clock: the verdict's headline.
    private var lockScreenInline: some View {
        Label(
            entry.day?.verdict?.headline ?? (entry.day == nil ? "SharpIt" : String(localized: "Verdict en attente")),
            systemImage: "circle.hexagongrid"
        )
    }

    /// Medium: the ring with its glyph, its name, its figure — a column of Résumé's strip.
    private func column(_ ring: WidgetResumeRing) -> some View {
        VStack(spacing: 5) {
            WidgetRing(fraction: ring.fraction, hue: ring.kind.hue, lineWidth: 5)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: ring.kind.symbol)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(ring.kind.hue)
                        .widgetAccentable()
                }
            Text(ring.kind.title)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(ring.value)
                .font(SharpitTypography.bodyEmphasis.monospacedDigit())
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.kind.title), \(ring.value)")
    }

    /// Small: the ring with its glyph inside — on a tinted or clear Home Screen the hues are
    /// gone, and four figures alone no longer say which ring is which.
    private func cell(_ ring: WidgetResumeRing) -> some View {
        WidgetRing(fraction: ring.fraction, hue: ring.kind.hue, lineWidth: 5)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: ring.kind.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(ring.kind.hue)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ring.kind.title), \(ring.value)")
    }
}

private extension WidgetResumeRing.Kind {
    var hue: Color {
        switch self {
        case .sleep: SharpitColor.pillarSleep
        case .recovery: SharpitColor.pillarRecovery
        case .nutrition: SharpitColor.pillarNutrition
        case .regularity: SharpitColor.pillarCoach
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "moon"
        case .recovery: "bolt"
        case .nutrition: "flame"
        case .regularity: "checkmark"
        }
    }

    var title: String {
        switch self {
        case .sleep: String(localized: "Sommeil")
        case .recovery: String(localized: "Récup.")
        case .nutrition: String(localized: "Nutrition")
        case .regularity: String(localized: "Régularité")
        }
    }
}
