import SwiftUI

/// « Ton déplacement à Lyon bouscule ton plan »: sessions ahead do not fit a trip or a
/// constraint (the server reads it, `docs/adr/0029`). One tap opens Plan's adapter with the trip
/// said; the card leaves by itself once the sessions fit.
struct TravelConflictCard: View {
    let conflict: V1TodayTravelConflict
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            SharpitCardHeader(
                title: TravelConflictReadout.title(conflict),
                symbol: conflict.type.symbol,
                subtitle: TravelConflictReadout.subtitle(conflict)
            )
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Ouvre l'ajustement du planning")
    }
}

enum TravelConflictReadout {
    static func title(_ conflict: V1TodayTravelConflict) -> String {
        if conflict.type == .constraint {
            return String(localized: "« \(conflict.name) » bouscule ton plan")
        }
        return String(localized: "Ton déplacement à \(conflict.name) bouscule ton plan")
    }

    /// « 2 séances ne collent pas, du sam. 7 au dim. 8 nov. ».
    static func subtitle(_ conflict: V1TodayTravelConflict) -> String {
        let count = conflict.sessionCount
        let sessions = count > 1
            ? String(localized: "\(count) séances ne collent pas")
            : String(localized: "1 séance ne colle pas")
        return "\(sessions), \(days(conflict))"
    }

    /// « le sam. 7 nov. » or « du sam. 7 au dim. 8 nov. ». The days are calendar days.
    static func days(_ conflict: V1TodayTravelConflict) -> String {
        guard let start = TrainingDayId.date(conflict.startDate) else { return "" }
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(SharpitLocale.current)
        guard conflict.endDate != conflict.startDate, let end = TrainingDayId.date(conflict.endDate) else {
            return String(localized: "le \(start.formatted(style))")
        }
        return String(localized: "du \(start.formatted(style)) au \(end.formatted(style))")
    }
}
