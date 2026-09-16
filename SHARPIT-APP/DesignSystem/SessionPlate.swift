import SwiftUI

struct SessionPlate: View {
    let session: SessionCardModel
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
                    if let meta = metaLine {
                        Text(meta)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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

    private var metaLine: String? {
        var parts: [String] = []
        if let sport = session.sport, !sport.isEmpty {
            parts.append(sport)
        }
        if session.priority {
            parts.append("Prioritaire")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
            metaLine,
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

private struct SessionMetricStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            configuration.label
            configuration.content
        }
    }
}
