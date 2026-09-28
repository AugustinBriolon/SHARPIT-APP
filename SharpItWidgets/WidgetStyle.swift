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

/// A sport's glyph in its identity color.
struct SportGlyph: View {
    let sport: V1ActivityType

    var body: some View {
        Image(systemName: sport.symbolName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(SharpitSportColor.color(sport.identity))
            .widgetAccentable()
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

/// Before the app has written today: what to do, with the brand mark — never yesterday's day.
struct WidgetAwaitingDay: View {
    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetEyebrow(text: eyebrow)
            Spacer(minLength: 0)
            Image(systemName: "circle.hexagonpath.fill")
                .font(.system(size: 22))
                .foregroundStyle(SharpitColor.primary)
            Text("Ouvre SharpIt pour charger ta journée.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
