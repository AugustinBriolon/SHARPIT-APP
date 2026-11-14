import SwiftUI

/// A session as a Clinique row (`docs/adr/0035`): the sport's glyph in a round tile, the session
/// as the title, sport and figures on one line under it, and at the end its status or the way in.
/// No surface of its own: it reads straight on the sheet, split from its neighbours by a hairline.
struct SessionPlate: View {
    let session: SessionCardModel
    /// Show "Prioritaire" only when several sessions compete (caller decides).
    var showPriorityTag: Bool = false
    var celebrateDone: Bool = false

    @State private var checkSettled = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CliniqueSportTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let meta {
                    Text(meta)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            trailing
        }
        .padding(.vertical, SharpitSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
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

    /// « Vélo · Seuil 3 × 12 min »: the sport, then the session's own name; a brick is its chain.
    private var headerTitle: String {
        if let chain = session.brickChain { return chain }
        guard let sport = session.sport, !sport.isEmpty else { return session.title }
        return ActivitySheetReadout.title(sport: sport, title: session.title)
    }

    /// A brick shows its first leg's glyph; the chain itself is the title.
    private var symbol: String {
        if let first = session.brickLegs?.first {
            return (V1ActivityType(rawValue: first.type) ?? .other).symbolName
        }
        return SharpitSportTone.symbolName(for: session.sport ?? "")
    }

    private var subtitle: String? {
        // A single session's sport already heads its title.
        let sport = session.brickLegs == nil ? nil : String(localized: "Brick")
        var parts: [String] = []
        for part in [sport, objectiveText].compactMap({ $0 }) where !part.isEmpty {
            // An objective that only repeats the sport adds nothing.
            if !parts.contains(where: { $0.localizedCaseInsensitiveCompare(part) == .orderedSame }) {
                parts.append(part)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// « Vélo · 1 h 30 · charge 85 »: the sport and objective, then the figures, on one line.
    private var meta: String? {
        var parts: [String] = []
        if showPriorityTag { parts.append(String(localized: "Prioritaire")) }
        if session.isKey, session.kind != .done { parts.append(String(localized: "Séance clé")) }
        if let subtitle { parts.append(subtitle) }
        parts += telemetryMetrics.map { metric in
            let unit = metric.unit.isEmpty ? "" : " \(metric.unit)"
            return "\(metric.label.lowercased()) \(metric.value)\(unit)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Done: its status, with the execution score once the analysis has run. Ahead: the way in.
    @ViewBuilder
    private var trailing: some View {
        if session.kind == .done {
            CliniqueStatusPill(
                session.complianceScore.map { "\($0) / 100" } ?? String(localized: "Faite"),
                status: .good
            )
            .scaleEffect(checkSettled ? 1.0 : 0.86)
            .opacity(checkSettled ? 1.0 : 0.4)
            .accessibilityHidden(true)
        } else {
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SharpitColor.slate)
                .accessibilityHidden(true)
        }
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
        let status = session.kind == .done ? String(localized: "Faite") : String(localized: "Prévue")
        let metrics = session.metrics.map { "\($0.label) \($0.value)\($0.unit)" }.joined(separator: ", ")
        return [
            session.brickLegs == nil ? session.sport : String(localized: "Brick"),
            showPriorityTag ? String(localized: "Prioritaire") : nil,
            session.isKey && session.kind != .done ? String(localized: "Séance clé") : nil,
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
        return legMetrics + [V1TodayMetric(label: String(localized: "Total"), value: "\(durations.reduce(0, +))", unit: "min")]
    }
}

enum SessionPriorityPolicy {
    static func showsTag(sessionCount: Int, priority: Bool) -> Bool {
        sessionCount > 1 && priority
    }
}
