import SwiftUI

/// A data card the coach's read tool returned (SHARPIT ADR-119): the day's scores, the effort
/// target, or sleep against readiness. Every figure is the tool's own; nothing here computes one.
///
/// A light card on the sheet: white inside a hairline, each figure beside its mark in a data hue.
/// It settles in as it arrives — a short rise and fade, a fade alone under Reduce Motion.
struct CoachDataCardView: View {
    let card: CoachDataCard

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch card {
            case .dayScores(let scores):
                CoachCardCaption(title: String(localized: "Scores du jour"), subtitle: CoachDataCardFormat.day(scores.trainingDayId)) { EmptyView() }
                dayScoreRows(scores)
            case .targetBand(let day, let band, let readiness):
                CoachCardCaption(title: String(localized: "Cible d'effort"), subtitle: CoachDataCardFormat.day(day)) {
                    if let status = CoachDataCardFormat.status(band.status) {
                        CliniqueStatusPill(status, status: band.status == "within" ? .good : .watch)
                    }
                }
                CoachTargetBandTrack(band: band, readiness: readiness)
            case .sleepVsReadiness(let windowDays, let points):
                CoachCardCaption(title: String(localized: "Sommeil et forme"), subtitle: String(localized: "\(windowDays) jours")) { EmptyView() }
                CoachSleepReadinessChart(points: points)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SharpitColor.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(SharpitColor.divider, lineWidth: 1))
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 10)
        .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.98, anchor: .top)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.86)) {
                hasAppeared = true
            }
        }
    }

    @ViewBuilder
    private func dayScoreRows(_ scores: CoachDataCard.DayScores) -> some View {
        VStack(spacing: 12) {
            if let readiness = scores.readiness {
                CoachScoreBar(title: String(localized: "Forme"), value: readiness, hue: SharpitColor.pillarRecovery, isShown: hasAppeared)
            }
            if let bank = scores.energyBank {
                CoachScoreBar(title: String(localized: "Réserve d'énergie"), value: bank.value, hue: SharpitColor.pillarSleep, isShown: hasAppeared)
            }
            if let stress = scores.stress {
                CoachScoreBar(title: String(localized: "Stress"), value: stress, hue: SharpitColor.pillarNutrition, isShown: hasAppeared)
            }
            if let band = scores.targetBand {
                HStack {
                    Text("Cible d'effort")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer(minLength: SharpitSpacing.xs)
                    Text(CoachDataCardFormat.band(band))
                        .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A score out of 100 on a thin bar in its hue, filling as the card arrives.
private struct CoachScoreBar: View {
    let title: String
    let value: Double
    let hue: Color
    let isShown: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: SharpitSpacing.xs)
                (Text(CoachDataCardFormat.score(value))
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    + Text(" / 100")
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(SharpitColor.slate))
            }
            SharpitBarTrack(fraction: isShown ? value / 100 : 0, tone: hue)
                .frame(height: 5)
                .animation(.easeOut(duration: 0.6).delay(0.1), value: isShown)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The day's effort window on a 0–100 track, the athlete's form marked on it.
private struct CoachTargetBandTrack: View {
    let band: CoachDataCard.Band
    let readiness: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(CoachDataCardFormat.band(band))
                    .font(SharpitTypography.system(size: 30, weight: .semibold, relativeTo: .title, digits: true))
                    .tracking(-0.8)
                    .foregroundStyle(SharpitColor.foreground)
                Text("fenêtre du jour")
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.slate)
            }
            // The window sits on the effort scale (0–21); the form is another scale, said apart.
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(SharpitColor.divider)
                    Capsule()
                        .fill(SharpitColor.pillarCoach)
                        .frame(width: max(width * CoachDataCardLayout.effortShare(band.high - band.low), 6))
                        .offset(x: width * CoachDataCardLayout.effortShare(band.low))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            HStack {
                Text(verbatim: "0")
                Spacer(minLength: 0)
                Text(verbatim: "21")
            }
            .font(SharpitTypography.system(size: 11, weight: .regular, relativeTo: .caption2, digits: true))
            .foregroundStyle(SharpitColor.slate)
            .accessibilityHidden(true)
            if let readiness {
                CliniqueDivider()
                HStack {
                    Text("Forme")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer(minLength: SharpitSpacing.xs)
                    Text("\(CoachDataCardFormat.score(readiness)) / 100")
                        .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Sleep as bars and readiness as a dot, a day a column; a tap on a day reads its two figures.
private struct CoachSleepReadinessChart: View {
    let points: [CoachDataCard.SleepPoint]
    @State private var selected: String?

    private var shown: CoachDataCard.SleepPoint? {
        points.first { $0.trainingDayId == selected } ?? points.last
    }

    var body: some View {
        let longest = max(points.compactMap(\.sleepMinutes).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 12) {
            if let shown {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(CoachDataCardFormat.day(shown.trainingDayId).capitalizedFirst)
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                    Spacer(minLength: 0)
                    legend(SharpitColor.pillarSleep, shown.sleepMinutes.map(CoachDataCardFormat.sleep) ?? "—")
                    legend(SharpitColor.pillarRecovery, shown.readiness.map { "\(CoachDataCardFormat.score($0)) / 100" } ?? "—")
                }
                .contentTransition(.numericText())
                .animation(SharpitMotion.selection, value: shown.trainingDayId)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(points, id: \.trainingDayId) { point in
                    let isShown = point.trainingDayId == shown?.trainingDayId
                    Button { selected = point.trainingDayId } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(SharpitColor.pillarSleep.opacity(isShown ? 1 : 0.25))
                                    .frame(height: max(64 * (point.sleepMinutes ?? 0) / longest, point.sleepMinutes == nil ? 0 : 4))
                                if let readiness = point.readiness {
                                    Circle()
                                        .fill(SharpitColor.pillarRecovery)
                                        .overlay(Circle().strokeBorder(SharpitColor.card, lineWidth: 1.5))
                                        .frame(width: 9, height: 9)
                                        .offset(y: -64 * CoachDataCardLayout.share(readiness) + 4)
                                }
                            }
                            .frame(height: 68, alignment: .bottom)
                            Text(CoachDataCardLayout.dayNumber(point.trainingDayId))
                                .font(SharpitTypography.system(size: 11, weight: isShown ? .semibold : .regular, relativeTo: .caption2, digits: true))
                                .foregroundStyle(isShown ? SharpitColor.foreground : SharpitColor.slate)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CoachDataCardFormat.day(point.trainingDayId))
                    .accessibilityValue([
                        point.sleepMinutes.map(CoachDataCardFormat.sleep),
                        point.readiness.map { String(localized: "forme \(CoachDataCardFormat.score($0))") },
                    ].compactMap { $0 }.joined(separator: ", "))
                }
            }
        }
    }

    private func legend(_ hue: Color, _ value: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(hue).frame(width: 7, height: 7)
            Text(value)
                .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote, digits: true))
                .foregroundStyle(SharpitColor.foreground)
        }
    }
}

/// Where a card's marks sit.
nonisolated enum CoachDataCardLayout {
    /// A 0–100 score as a share of a track, kept inside it.
    static func share(_ score: Double) -> Double {
        guard score.isFinite else { return 0 }
        return min(max(score / 100, 0), 1)
    }

    /// An effort figure (0–21, the day's strain scale) as a share of its track.
    static func effortShare(_ effort: Double) -> Double {
        guard effort.isFinite else { return 0 }
        return min(max(effort / 21, 0), 1)
    }

    /// « 14 » from `2026-11-14`: the day under a column.
    static func dayNumber(_ trainingDayId: String) -> String {
        trainingDayId.split(separator: "-").last.flatMap { Int($0) }.map(String.init) ?? ""
    }
}

/// A data card's head: what the card reads and for which day, with an optional pill at the
/// trailing edge.
private struct CoachCardCaption<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
            Text(title)
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                .foregroundStyle(SharpitColor.foreground)
            Text(subtitle)
                .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(1)
            Spacer(minLength: SharpitSpacing.xs)
            accessory()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
