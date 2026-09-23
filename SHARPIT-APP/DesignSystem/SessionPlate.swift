import SwiftUI

/// An Apple Design Award-grade session instrument card following Golden Ratio spatial harmony.
///
/// Hierarchy:
/// 1. Top Bar: Sport identity badge with native SF Symbol, priority star, and status/chevron affordance.
/// 2. Body: Session title with high-contrast Syne typography + extracted contextual objective chip.
/// 3. Telemetry: Fine hairline divider + proportionate quantitative metrics with baseline alignment.
struct SessionPlate: View {
    let session: SessionCardModel
    /// Show "Prioritaire" only when several sessions compete (caller decides).
    var showPriorityTag: Bool = false
    var celebrateDone: Bool = false

    @State private var checkSettled = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            // Zone 1: Identity & Status Header
            headerRow

            // Zone 2: Title & Contextual Objective
            titleAndObjectiveBlock

            // Zone 3: Proportional Telemetry Row
            if !telemetryMetrics.isEmpty {
                telemetryGrid
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .sharpitCardSpecularBorder()
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

    // MARK: – Zone 1: Header Row

    private var headerRow: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.xs) {
            // Sport Identity Capsule with SF Symbol
            if let sport = session.sport, !sport.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: SharpitSportTone.symbolName(for: sport))
                        .font(.system(size: 11, weight: .semibold))

                    Text(sport.uppercased())
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                }
                .foregroundStyle(SharpitSportTone.label(for: sport))
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(SharpitSportTone.background(for: sport), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(SharpitSportTone.border(for: sport), lineWidth: SharpitStroke.hairline)
                )
            }

            // Priority Indicator
            if showPriorityTag {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))

                    Text("PRIORITAIRE")
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                }
                .foregroundStyle(SharpitColor.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SharpitColor.highlight.opacity(0.22), in: Capsule())
            }

            Spacer(minLength: SharpitSpacing.xs)

            // Status Badge & Action Affordance
            if session.kind == .done {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(SharpitColor.signalRecovery)

                        Text("FAITE")
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .foregroundStyle(SharpitColor.signalRecovery)
                    }
                    .scaleEffect(checkSettled ? 1.0 : 0.86)
                    .opacity(checkSettled ? 1.0 : 0.4)
                    .accessibilityHidden(true)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                        .accessibilityHidden(true)
                }
            } else {
                HStack(spacing: 6) {
                    Text("PRÉVUE")
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .foregroundStyle(SharpitColor.mutedForeground)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SharpitColor.mutedForeground.opacity(0.45))
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: – Zone 2: Title & Objective

    private var titleAndObjectiveBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title)
                .font(.custom(SharpitFontFamily.heading.resolvedName(for: .semibold) ?? "System", size: 18, relativeTo: .title3))
                .tracking(-0.3)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Extracted Objective context pill (No longer squished in 3-column grid)
            if let objective = objectiveText {
                HStack(spacing: 5) {
                    Image(systemName: "target")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SharpitColor.primary)

                    Text(objective)
                        .font(.custom(SharpitFontFamily.body.resolvedName(for: .medium) ?? "System", size: 12.5))
                        .foregroundStyle(SharpitColor.foreground.opacity(0.85))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                        .fill(SharpitColor.secondary.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: SharpitSpacing.chipRadius, style: .continuous)
                                .strokeBorder(SharpitColor.border.opacity(0.06), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    // MARK: – Zone 3: Proportional Telemetry Grid

    private var telemetryGrid: some View {
        VStack(spacing: 10) {
            // Fine hairline separator
            Rectangle()
                .fill(SharpitColor.border.opacity(0.55))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(telemetryMetrics.enumerated()), id: \.element.label) { index, metric in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(metric.label)
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(SharpitColor.mutedForeground)

                        metricValueView(metric: metric)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if index < telemetryMetrics.count - 1 {
                        Spacer(minLength: SharpitSpacing.xs)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metricValueView(metric: V1TodayMetric) -> some View {
        let isTextual = metric.unit.isEmpty && !metric.value.contains(where: { $0.isNumber })

        if isTextual {
            // Qualitative metric (e.g. Intensité: Endurance)
            HStack(spacing: 5) {
                Circle()
                    .fill(intensityColor(for: metric.value))
                    .frame(width: 6.5, height: 6.5)

                Text(metric.value)
                    .font(.custom(SharpitFontFamily.body.resolvedName(for: .semibold) ?? "System", size: 15))
                    .foregroundStyle(SharpitColor.foreground)
            }
            .padding(.top, 1)
        } else {
            // Quantitative telemetry (e.g. Durée: 45 min, Charge: 50 TSS)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.value)
                    .font(.custom(SharpitFontFamily.data.resolvedName(for: .medium) ?? "Menlo", size: 19))
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)

                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.custom(SharpitFontFamily.body.resolvedName(for: .regular) ?? "System", size: 12))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
        }
    }

    private func intensityColor(for value: String) -> Color {
        let lower = value.lowercased()
        if lower.contains("endurance") || lower.contains("recup") || lower.contains("faible") {
            return SharpitColor.signalRecovery
        } else if lower.contains("seuil") || lower.contains("tempo") || lower.contains("moyen") {
            return SharpitColor.highlight
        } else if lower.contains("vma") || lower.contains("max") || lower.contains("eleve") || lower.contains("intens") {
            return SharpitColor.destructive
        }
        return SharpitColor.primary
    }

    // MARK: – Data Partitioning

    /// Extracts objective from metrics or subtitle so it doesn't break the horizontal metric grid.
    private var objectiveText: String? {
        if let objMetric = session.metrics.first(where: {
            let label = $0.label.lowercased()
            return label.contains("objectif") || label.contains("goal") || label.contains("target")
        }) {
            return objMetric.value
        }
        if showsSubtitle, let subtitle = session.subtitle, !subtitle.isEmpty {
            return subtitle
        }
        return nil
    }

    /// Clean telemetry metrics excluding long objective strings.
    private var telemetryMetrics: [V1TodayMetric] {
        session.metrics.filter { metric in
            let label = metric.label.lowercased()
            return !label.contains("objectif") && !label.contains("goal") && !label.contains("target")
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
            objectiveText != nil ? "Objectif: \(objectiveText!)" : nil,
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
