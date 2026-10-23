import SwiftUI
import WidgetKit

/// The ink plate behind a widget, as the app's lead card and the Live Activities (ADR-085): lime
/// glyphs and white figures on ink read from across the Home Screen, in light and dark alike.
///
/// Clipped to `ContainerRelativeShape` so the fill follows Apple's continuous widget corner —
/// the same radius Weather and Calendar use — instead of reading as a tighter card inside it.
/// A tinted or clear Home Screen removes it, as it removes every container background.
struct WidgetCanvas: View {
    var body: some View {
        SharpitColor.inkSurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(ContainerRelativeShape())
    }
}

extension View {
    /// Every widget's chrome: the ink plate, and the content read as on a dark surface so the
    /// tokens resolve to white figures and muted captions on it.
    func sharpitWidgetChrome() -> some View {
        environment(\.colorScheme, .dark)
            .containerBackground(for: .widget) { WidgetCanvas() }
    }
}

/// A small uppercase line over a block — the app's eyebrow.
struct WidgetEyebrow: View {
    let text: String
    var tint: Color = SharpitColor.mutedForeground

    var body: some View {
        Text(text)
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

/// A figure as the app reads one: the number in the instrument face, its unit beside it, quieter.
struct WidgetFigure: View {
    let figure: WidgetSnapshot.Figure
    var large = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(figure.value)
                .font(large ? SharpitTypography.data : SharpitTypography.instrument)
                .tracking(large ? SharpitTypography.dataTracking : 0)
                .foregroundStyle(SharpitColor.foreground)
                .monospacedDigit()
            Text(figure.unit)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// A row of figures that never truncates: the large face if all fit, else the body face, else
/// the first figure alone, then that figure shrunk — a cut « 1:2… » reads as broken, a dropped second
/// figure does not.
struct WidgetFigureRow: View {
    let figures: [WidgetSnapshot.Figure]
    var spacing: CGFloat = 12

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(figures, large: true)
            row(figures, large: false)
            row(Array(figures.prefix(1)), large: false)
            // Last resort for one figure wider than the widget: it shrinks rather than spill.
            if let first = figures.first {
                WidgetFigure(figure: first).minimumScaleFactor(0.5)
            }
        }
    }

    private func row(_ shown: [WidgetSnapshot.Figure], large: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, figure in
                WidgetFigure(figure: figure, large: large)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

/// Done: a filled check — a status mark, the one place a symbol is filled.
struct DoneSeal: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(SharpitColor.inkAccent)
            .widgetAccentable()
            .accessibilityLabel("Faite")
    }
}

/// The day the widget speaks of — « Lun. 28 ».
enum WidgetDay {
    static func label(_ trainingDayId: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: trainingDayId) else { return String(localized: "Aujourd'hui") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().locale(AppLanguage.locale))
    }
}

/// Every home-screen widget's frame: one header — its name and one glyph, the same height on
/// every widget — then the body, anchored to the bottom, inside the system's content margins.
/// Written once so no widget drifts a point from the others: a header without a glyph, a
/// glyph of another size, a body starting higher.
struct WidgetFrame<Glyph: View, Content: View>: View {
    let title: String
    @ViewBuilder let glyph: Glyph
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                WidgetEyebrow(text: title)
                Spacer(minLength: 4)
                glyph
                    .font(.system(size: WidgetMetrics.glyphSize, weight: .semibold))
                    .frame(height: WidgetMetrics.headerHeight)
            }
            .frame(height: WidgetMetrics.headerHeight)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.top, WidgetMetrics.headerGap)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension WidgetFrame where Glyph == WidgetGlyph {
    init(_ title: String, symbol: String, tint: Color = SharpitColor.mutedForeground, @ViewBuilder content: () -> Content) {
        self.init(title: title, glyph: { WidgetGlyph(symbol: symbol, tint: tint) }, content: content)
    }
}

/// The header's glyph: stroked, muted unless it carries a state or a sport.
struct WidgetGlyph: View {
    let symbol: String
    var tint: Color = SharpitColor.mutedForeground

    var body: some View {
        Image(sharpitSymbol: symbol)
            .foregroundStyle(tint)
            .widgetAccentable()
    }
}

/// The widgets' one set of measures.
enum WidgetMetrics {
    static let headerHeight: CGFloat = 18
    static let glyphSize: CGFloat = 14
    static let headerGap: CGFloat = 8
    /// Between the hero figure and the lines under it.
    static let lineGap: CGFloat = 4
    /// Nested panels — same continuous corner as the app ink verdict (`SharpitRadius.panel`).
    static let panelRadius: CGFloat = 18
}

/// The widget's main number, the same face and size on every widget, its unit beside it.
struct WidgetHero: View {
    let value: String
    var unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(SharpitTypography.heroScore)
                .tracking(SharpitTypography.heroScoreTracking)
                .foregroundStyle(SharpitColor.foreground)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let unit, !unit.isEmpty {
                Text(unit)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }
        }
    }
}

/// A widget's title line — a session, a verdict, a race: the section face, everywhere.
struct WidgetTitle: View {
    let text: String
    var lines = 2

    var body: some View {
        Text(text)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
            .lineLimit(lines)
            .minimumScaleFactor(0.85)
    }
}

/// A quiet line under the figure or the title.
struct WidgetCaption: View {
    let text: String
    var tint: Color = SharpitColor.mutedForeground
    var lines = 1

    var body: some View {
        Text(text)
            .font(SharpitTypography.meta.monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(lines)
    }
}

/// A section the app has not written yet: where to open it, with the brand mark.
struct WidgetAwaitingData: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "circle.hexagonpath.fill")
                .font(.system(size: 20))
                .foregroundStyle(SharpitColor.inkAccent)
            WidgetCaption(text: text, lines: 3)
        }
    }
}

/// Before the app has written today: its header, what to do — never yesterday's day.
struct WidgetAwaitingDay: View {
    let eyebrow: String
    let symbol: String

    var body: some View {
        WidgetFrame(eyebrow, symbol: symbol) {
            WidgetAwaitingData(text: String(localized: "Ouvre SharpIt pour charger ta journée."))
        }
    }
}

/// An extra widget below SharpIt Pro: what it would show, and where to get it.
struct WidgetProLocked: View {
    let title: String
    let symbol: String
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "lock").font(.title3)
            }
        case .accessoryRectangular, .accessoryInline:
            Label("\(title) · SharpIt Pro", systemImage: "lock")
                .font(.headline)
        default:
            WidgetFrame(title, symbol: symbol) {
                WidgetCaption(text: String(localized: "Widget SharpIt Pro. Passe à Pro dans Paramètres pour l'afficher."), lines: 4)
            }
        }
    }
}

/// A widget whose feature the athlete turned off in Paramètres: it says so rather than show a
/// part of SharpIt they chose to hide. The system keeps a placed widget; only they can remove it.
struct WidgetFeatureOff: View {
    let feature: SharpitFeature
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: feature.symbolName).font(.title3)
            }
        case .accessoryRectangular, .accessoryInline:
            Label("\(feature.title) masqué", systemImage: feature.symbolName)
                .font(.headline)
        default:
            WidgetFrame(feature.title, symbol: feature.symbolName) {
                WidgetCaption(text: String(localized: "Masqué dans SharpIt. Réactive-le dans Paramètres › Pages et widgets."), lines: 4)
            }
        }
    }
}
