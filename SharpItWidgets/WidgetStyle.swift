import SwiftUI
import WidgetKit

/// The app's canvas behind a widget: Snow White or Forest Night, the dot grid and the two brand
/// halos — `SharpitCanvasTexture`, the very one the app draws. A verdict adds a halo in its
/// posture's tone: color is state, never decoration.
struct WidgetCanvas: View {
    var stateTone: Color?

    var body: some View {
        ZStack {
            SharpitColor.background
            SharpitCanvasTexture()
            if let stateTone {
                RadialGradient(colors: [stateTone.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 170)
            }
        }
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

/// Done: a filled check — a status mark, the one place a symbol is filled.
struct DoneSeal: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(SharpitColor.primary)
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
        guard let date = parser.date(from: trainingDayId) else { return "Aujourd'hui" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().locale(Locale(identifier: "fr_FR")))
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
        Image(systemName: symbol)
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
                .foregroundStyle(SharpitColor.primary)
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
            WidgetAwaitingData(text: "Ouvre SharpIt pour charger ta journée.")
        }
    }
}
