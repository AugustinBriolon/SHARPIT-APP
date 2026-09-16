import SwiftUI

struct SessionPlate: View {
    let session: SessionCardModel
    var celebrateDone: Bool = false

    @State private var checkSettled = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .center, spacing: SharpitSpacing.xs) {
                Image(systemName: session.kind == .done ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(session.kind == .done ? Color.accentColor : .secondary)
                    .scaleEffect(checkSettled || session.kind != .done ? 1.0 : 0.86)
                    .opacity(checkSettled || session.kind != .done ? 1.0 : 0.4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    tagRow
                    Text(session.title)
                        .font(.headline)
                    if let subtitle = session.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if !session.metrics.isEmpty {
                HStack(spacing: SharpitSpacing.md) {
                    ForEach(session.metrics, id: \.label) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.label)
                                .font(SharpitTypography.label())
                                .tracking(SharpitTypography.labelTracking)
                                .textCase(.uppercase)
                                .foregroundStyle(.tertiary)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(metric.value)
                                    .font(SharpitTypography.data())
                                Text(metric.unit)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 36)
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
        if session.sport != nil || session.priority {
            HStack(spacing: 6) {
                if let sport = session.sport {
                    Text(sport)
                        .font(SharpitTypography.label())
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                if session.priority {
                    Text("Prioritaire")
                        .font(SharpitTypography.label())
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SharpitInk.highlight.opacity(0.35), in: Capsule())
                }
            }
        }
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
        return [session.sport, session.priority ? "Prioritaire" : nil, session.title, session.subtitle, status, metrics]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
