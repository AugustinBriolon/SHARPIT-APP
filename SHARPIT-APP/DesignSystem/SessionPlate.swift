import SwiftUI

/// A session as an Ink & Lime card (ADR-085): the sport's icon tile, the session as the title,
/// sport and objective as the subtitle, its status as a pill; then its figures in a stat row.
struct SessionPlate: View {
    let session: SessionCardModel
    /// Show "Prioritaire" only when several sessions compete (caller decides).
    var showPriorityTag: Bool = false
    var celebrateDone: Bool = false

    @State private var checkSettled = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(
                title: session.brickChain ?? session.title,
                symbol: symbol,
                subtitle: subtitle
            ) {
                statusPills
            }

            if !telemetryMetrics.isEmpty {
                Divider().overlay(SharpitColor.border)
                HStack(alignment: .top, spacing: SharpitSpacing.md) {
                    ForEach(telemetryMetrics, id: \.label) { metric in
                        SharpitStatTile(
                            caption: metric.label,
                            value: metric.value,
                            unit: metric.unit.isEmpty ? nil : metric.unit,
                            isFlat: true
                        )
                    }
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

    // MARK: – Header

    /// A brick shows its first leg's glyph; the chain itself is the title.
    private var symbol: String {
        if let first = session.brickLegs?.first {
            return (V1ActivityType(rawValue: first.type) ?? .other).symbolName
        }
        return SharpitSportTone.symbolName(for: session.sport ?? "")
    }

    private var subtitle: String? {
        let sport = session.brickLegs == nil ? session.sport : "Brick"
        var parts: [String] = []
        for part in [sport, objectiveText].compactMap({ $0 }) where !part.isEmpty {
            // An objective that only repeats the sport adds nothing.
            if !parts.contains(where: { $0.localizedCaseInsensitiveCompare(part) == .orderedSame }) {
                parts.append(part)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusPills: some View {
        HStack(spacing: SharpitSpacing.xxs + 2) {
            if showPriorityTag {
                SharpitPill("Prioritaire", style: .limeSoft)
            }
            // A session still to do that carries the week; once done, « Faite » says enough.
            if session.isKey, session.kind != .done {
                SharpitPill("Clé", style: .lime)
            }
            if session.kind == .done {
                SharpitPill("Faite", style: .lime)
                    .scaleEffect(checkSettled ? 1.0 : 0.86)
                    .opacity(checkSettled ? 1.0 : 0.4)
            } else {
                SharpitPill("Prévue", style: .neutral)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: – Data Partitioning

    /// Extracts objective from metrics or subtitle so it doesn't break the horizontal metric grid.
    private var objectiveText: String? {
        // A brick's subtitle repeats its duration; only the goal it serves is worth a pill.
        if session.brickLegs != nil {
            return session.subtitle?
                .components(separatedBy: " · ")
                .first { $0.hasPrefix("Sert ") }
                .map { String($0.dropFirst(5)) }
        }
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
        if let legMetrics = session.brickLegMetrics { return legMetrics }
        return session.metrics.filter { metric in
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
            session.brickLegs == nil ? session.sport : "Brick",
            showPriorityTag ? "Prioritaire" : nil,
            session.isKey && session.kind != .done ? "Séance clé" : nil,
            session.brickChain ?? session.title,
            objectiveText != nil ? "Objectif: \(objectiveText!)" : nil,
            status,
            metrics,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}

extension SessionCardModel {
    /// « Vélo → Course » for a brick line, nil otherwise.
    var brickChain: String? {
        brickLegs.map { legs in
            legs.map { (V1ActivityType(rawValue: $0.type) ?? .other).label }.joined(separator: " → ")
        }
    }

    /// A brick's telemetry: each leg's length in order, then the whole — what the plate
    /// reads across, as the chain is done.
    var brickLegMetrics: [V1TodayMetric]? {
        guard let legs = brickLegs else { return nil }
        let legMetrics = legs.map { leg in
            V1TodayMetric(
                label: (V1ActivityType(rawValue: leg.type) ?? .other).label,
                value: leg.durationMin.map(String.init) ?? "–",
                unit: leg.durationMin == nil ? "" : "min"
            )
        }
        let durations = legs.compactMap(\.durationMin)
        guard durations.count == legs.count else { return legMetrics }
        return legMetrics + [V1TodayMetric(label: "Total", value: "\(durations.reduce(0, +))", unit: "min")]
    }
}

enum SessionPriorityPolicy {
    static func showsTag(sessionCount: Int, priority: Bool) -> Bool {
        sessionCount > 1 && priority
    }
}
