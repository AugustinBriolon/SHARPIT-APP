import SwiftUI

struct SessionPlate: View {
    let session: SessionCardModel
    /// Show "Prioritaire" only when several sessions compete (caller decides).
    var showPriorityTag: Bool = false
    var celebrateDone: Bool = false

    @State private var checkSettled = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xxs) {
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    tagRow
                    Text(session.title)
                        .font(SharpitTypography.cardTitle)
                        .tracking(SharpitTypography.cardTitleTracking)
                    if showsSubtitle, let subtitle = session.subtitle {
                        Text(subtitle)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                Spacer(minLength: 0)
            }
            if !session.metrics.isEmpty {
                HStack(alignment: .top, spacing: SharpitSpacing.md) {
                    ForEach(session.metrics, id: \.label) { metric in
                        LabeledContent {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(metric.value)
                                    .font(SharpitTypography.data)
                                if !metric.unit.isEmpty {
                                    Text(metric.unit)
                                        .font(SharpitTypography.meta)
                                        .foregroundStyle(SharpitColor.mutedForeground)
                                }
                            }
                        } label: {
                            Text(metric.label)
                                .font(SharpitTypography.label)
                                .tracking(SharpitTypography.labelTracking)
                                .textCase(.uppercase)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                        .labeledContentStyle(SessionMetricStyle())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            guard session.kind == .done else {
                checkSettled = true
                return
            }
            if celebrateDone {
                playDoneCelebration()
            } else if SharpitMotion.reduceMotion {
                checkSettled = true
            } else {
                SharpitMotion.run {
                    checkSettled = true
                }
            }
        }
        .onChange(of: celebrateDone) { _, shouldCelebrate in
            guard shouldCelebrate, session.kind == .done else { return }
            playDoneCelebration()
        }
    }

    @ViewBuilder
    private var tagRow: some View {
        if session.sport != nil || showPriorityTag || session.kind == .done {
            HStack(spacing: SharpitSpacing.xs) {
                if let sport = session.sport, !sport.isEmpty {
                    Text(sport)
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitSportTone.accent(for: sport))
                        .padding(.horizontal, SharpitSpacing.xs)
                        .padding(.vertical, SharpitSpacing.xxs)
                        .background(SharpitSportTone.background(for: sport), in: Capsule())
                        .overlay(Capsule().strokeBorder(SharpitSportTone.border(for: sport), lineWidth: SharpitStroke.hairline))
                }
                if showPriorityTag {
                    Text("Prioritaire")
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                if session.kind == .done {
                    // Opposite the sport tag on the same line: the badge says what the
                    // session was, the mark says it happened — they read as one row.
                    Spacer(minLength: SharpitSpacing.xs)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(SharpitColor.primary)
                        .scaleEffect(checkSettled ? 1.0 : 0.86)
                        .opacity(checkSettled ? 1.0 : 0.4)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// Drop subtitle when it mostly repeats the metrics row.
    private var showsSubtitle: Bool {
        guard let subtitle = session.subtitle, !subtitle.isEmpty else { return false }
        guard !session.metrics.isEmpty else { return true }
        let metricTokens = session.metrics.flatMap { metric in
            [metric.value, metric.unit].filter { !$0.isEmpty }
        }
        let hits = metricTokens.filter { subtitle.localizedCaseInsensitiveContains($0) }.count
        return hits < 2
    }

    private func playDoneCelebration() {
        SharpitHaptics.play(.success)
        if SharpitMotion.reduceMotion {
            checkSettled = true
            return
        }
        checkSettled = false
        SharpitMotion.run {
            checkSettled = true
        }
    }

    private var accessibilityLabel: String {
        let status = session.kind == .done ? "Faite" : "Prévue"
        let metrics = session.metrics.map { "\($0.label) \($0.value)\($0.unit)" }.joined(separator: ", ")
        return [
            session.sport,
            showPriorityTag ? "Prioritaire" : nil,
            session.title,
            showsSubtitle ? session.subtitle : nil,
            status,
            metrics,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}

enum SessionPriorityPolicy {
    static func showsTag(sessionCount: Int, priority: Bool) -> Bool {
        sessionCount > 1 && priority
    }
}

private struct SessionMetricStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            configuration.label
            configuration.content
        }
    }
}
