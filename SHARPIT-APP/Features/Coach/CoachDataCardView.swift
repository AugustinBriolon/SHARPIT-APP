import SwiftUI

/// A data card the coach's read tool returned (SHARPIT ADR-119): the day's scores, the effort
/// target, or sleep against readiness. Every figure is the tool's own; nothing here computes one.
struct CoachDataCardView: View {
    let card: CoachDataCard

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            switch card {
            case .dayScores(let scores):
                CoachCardCaption(title: String(localized: "Scores du jour"), subtitle: CoachDataCardFormat.day(scores.trainingDayId)) { EmptyView() }
                dayScoreRows(scores)
            case .targetBand(let day, let band, let readiness):
                CoachCardCaption(title: String(localized: "Cible d'effort"), subtitle: CoachDataCardFormat.day(day)) {
                    if let status = CoachDataCardFormat.status(band.status) { SharpitPill(status) }
                }
                SharpitInsetGroup {
                    SharpitInsetRow(title: String(localized: "Fenêtre du jour")) {
                        EmptyView()
                    } trailing: {
                        SharpitRowFigure(value: CoachDataCardFormat.band(band))
                    }
                    if let readiness {
                        scoreRow(String(localized: "Forme"), readiness)
                    }
                }
            case .sleepVsReadiness(let windowDays, let points):
                CoachCardCaption(title: String(localized: "Sommeil et forme"), subtitle: String(localized: "\(windowDays) jours")) { EmptyView() }
                SharpitInsetGroup {
                    ForEach(points, id: \.trainingDayId) { point in
                        SharpitInsetRow(title: CoachDataCardFormat.day(point.trainingDayId)) {
                            EmptyView()
                        } trailing: {
                            HStack(spacing: SharpitSpacing.sm) {
                                SharpitRowFigure(value: point.sleepMinutes.map(CoachDataCardFormat.sleep) ?? "—")
                                SharpitRowFigure(value: point.readiness.map(CoachDataCardFormat.score) ?? "—", unit: "/100")
                            }
                        }
                    }
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    @ViewBuilder
    private func dayScoreRows(_ scores: CoachDataCard.DayScores) -> some View {
        SharpitInsetGroup {
            if let bank = scores.energyBank {
                scoreRow(String(localized: "Réserve d'énergie"), bank.value)
            }
            if let stress = scores.stress {
                scoreRow(String(localized: "Stress"), stress)
            }
            if let band = scores.targetBand {
                SharpitInsetRow(title: String(localized: "Cible d'effort")) {
                    EmptyView()
                } trailing: {
                    SharpitRowFigure(value: CoachDataCardFormat.band(band))
                }
            }
            if let readiness = scores.readiness {
                scoreRow(String(localized: "Forme"), readiness)
            }
        }
    }

    private func scoreRow(_ title: String, _ value: Double) -> some View {
        SharpitInsetRow(title: title) {
            EmptyView()
        } trailing: {
            SharpitRowFigure(value: CoachDataCardFormat.score(value), unit: "/100")
        }
    }
}

/// A data card's head, as the mock-up draws it: what the card reads and for which day, quietly,
/// with an optional pill at the trailing edge.
private struct CoachCardCaption<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
            Text("\(title) · \(subtitle)")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: SharpitSpacing.xs)
            accessory()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
