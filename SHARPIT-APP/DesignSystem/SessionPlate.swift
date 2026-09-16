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
                if session.kind == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .scaleEffect(checkSettled ? 1.0 : 0.86)
                        .opacity(checkSettled ? 1.0 : 0.4)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    tagRow
                    Text(session.title)
                        .font(.headline)
                    if showsSubtitle, let subtitle = session.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                                    .font(SharpitTypography.data())
                                if !metric.unit.isEmpty {
                                    Text(metric.unit)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            Text(metric.label)
                                .font(SharpitTypography.label())
                                .tracking(SharpitTypography.labelTracking)
                                .textCase(.uppercase)
                                .foregroundStyle(.tertiary)
                        }
                        .labeledContentStyle(SessionMetricStyle())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitGlassCard()
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
        if session.sport != nil || showPriorityTag {
            HStack(spacing: 6) {
                if let sport = session.sport, !sport.isEmpty {
                    Text(sport)
                        .font(SharpitTypography.label())
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitSportTone.foreground(for: sport))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SharpitSportTone.background(for: sport), in: Capsule())
                }
                if showPriorityTag {
                    Text("Prioritaire")
                        .font(SharpitTypography.label())
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: Capsule())
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

enum SharpitSportTone {
    static func background(for sport: String) -> Color {
        switch normalized(sport) {
        case let s where s.contains("course") || s.contains("run"):
            return Color.orange.opacity(0.18)
        case let s where s.contains("velo") || s.contains("cycl") || s.contains("bike"):
            return Color.blue.opacity(0.14)
        case let s where s.contains("natation") || s.contains("swim"):
            return Color.cyan.opacity(0.16)
        case let s where s.contains("force") || s.contains("muscu") || s.contains("gym"):
            return Color.purple.opacity(0.14)
        default:
            return Color.primary.opacity(0.08)
        }
    }

    static func foreground(for sport: String) -> Color {
        switch normalized(sport) {
        case let s where s.contains("course") || s.contains("run"):
            return Color.orange
        case let s where s.contains("velo") || s.contains("cycl") || s.contains("bike"):
            return Color.blue
        case let s where s.contains("natation") || s.contains("swim"):
            return Color.cyan
        case let s where s.contains("force") || s.contains("muscu") || s.contains("gym"):
            return Color.purple
        default:
            return Color.secondary
        }
    }

    private static func normalized(_ sport: String) -> String {
        sport
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
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
