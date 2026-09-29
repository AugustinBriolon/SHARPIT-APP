import SwiftUI

/// One line of the technical reading: the figure, and what it says in a few words.
struct ActivityTechnicalRow: Equatable, Identifiable {
    let label: String
    let value: String
    var note: String?

    var id: String { label }
}

/// How the expert reading names a session's analysis — the web's `buildPerformanceRows`, in the
/// same order and the same words, so a figure reads the same on both.
enum ActivityTechnicalReadout {
    static func rows(_ analysis: V1ActivityAnalysis) -> [ActivityTechnicalRow] {
        var rows: [ActivityTechnicalRow] = []
        let french = Locale(identifier: "fr_FR")
        func decimal(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(2)).locale(french))
        }

        if let power = analysis.power, let normalized = power.normalized {
            rows.append(ActivityTechnicalRow(
                label: "NP",
                value: "\(Int(normalized.rounded())) W",
                note: power.avg.map { "moy \(Int($0.rounded())) W" }
            ))
        }
        if let intensityFactor = analysis.load?.intensityFactor {
            rows.append(ActivityTechnicalRow(label: "IF", value: decimal(intensityFactor), note: intensityReference(analysis)))
        }
        if let variability = analysis.power?.variabilityIndex {
            rows.append(ActivityTechnicalRow(
                label: "VI",
                value: decimal(variability),
                note: variability > 1.1 ? "effort variable" : "effort régulier"
            ))
        }
        if let tss = analysis.load?.tss {
            rows.append(ActivityTechnicalRow(label: analysis.load?.method == "hr" ? "TSS (FC)" : "TSS", value: "\(Int(tss.rounded()))"))
        }
        if let efficiency = analysis.hr?.efficiencyFactor {
            rows.append(ActivityTechnicalRow(
                label: analysis.hr?.efficiencyLabel ?? "Facteur d'efficacité",
                value: efficiency.formatted(.number.locale(french))
            ))
        }
        if let decoupling = analysis.hr?.decouplingPct {
            let sign = decoupling > 0 ? "+" : ""
            rows.append(ActivityTechnicalRow(
                label: "Découplage",
                value: "\(sign)\(decoupling.formatted(.number.precision(.fractionLength(0...1)).locale(french))) %",
                note: decouplingNote(abs(decoupling))
            ))
        }
        if let paceVariability = analysis.run?.paceVariabilityPct {
            rows.append(ActivityTechnicalRow(
                label: "Variabilité allure",
                value: "\(paceVariability.formatted(.number.precision(.fractionLength(0...1)).locale(french))) %",
                note: "écart-type / moyenne"
            ))
        }
        return rows
    }

    /// « FTP 250 W · LTHR 168 bpm · estimés » — the references the figures were read against.
    static func thresholdsLine(_ analysis: V1ActivityAnalysis) -> String? {
        guard let thresholds = analysis.thresholds else { return nil }
        let parts = [
            thresholds.ftp.map { "FTP \(Int($0.rounded())) W" },
            thresholds.lthr.map { "LTHR \(Int($0.rounded())) bpm" },
            thresholds.maxHr.map { "FC max \(Int($0.rounded())) bpm" },
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        let origin = thresholds.source == "estimate" ? "seuils estimés" : "seuils du profil"
        return (parts + [origin]).joined(separator: " · ")
    }

    /// Zones the session actually spent time in.
    static func zones(_ zones: [V1ActivityAnalysis.Zone]?) -> [V1ActivityAnalysis.Zone] {
        let zones = zones ?? []
        return zones.contains { $0.seconds > 0 } ? zones : []
    }

    private static func intensityReference(_ analysis: V1ActivityAnalysis) -> String? {
        if analysis.load?.method == "power" {
            return analysis.thresholds?.ftp.map { "FTP \(Int($0.rounded())) W" }
        }
        return analysis.thresholds?.lthr.map { "LTHR \(Int($0.rounded())) bpm" }
    }

    private static func decouplingNote(_ magnitude: Double) -> String {
        if magnitude < 5 { return "Peu de dérive cardiaque" }
        if magnitude < 10 { return "Correct pour une sortie longue" }
        return "Dérive élevée : chaleur, fatigue ou endurance"
    }
}

/// « Analyse technique »: the expert reading of a session — its figures, then the time spent in
/// each zone, then the thresholds they were read against. Absent in the essential reading
/// (ADR 0006): no teaser, no lock.
struct ActivityTechnicalSection: View {
    let analysis: V1ActivityAnalysis

    private var rows: [ActivityTechnicalRow] { ActivityTechnicalReadout.rows(analysis) }
    private var heartZones: [V1ActivityAnalysis.Zone] { ActivityTechnicalReadout.zones(analysis.hr?.zones) }
    private var powerZones: [V1ActivityAnalysis.Zone] { ActivityTechnicalReadout.zones(analysis.power?.zones) }

    var isEmpty: Bool { rows.isEmpty && heartZones.isEmpty && powerZones.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitEyebrow("Analyse technique")
            if !rows.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: SharpitSpacing.md, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                    alignment: .leading,
                    spacing: SharpitSpacing.md
                ) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(SharpitTypography.label)
                                .tracking(SharpitTypography.labelTracking)
                                .textCase(.uppercase)
                                .foregroundStyle(SharpitColor.mutedForeground)
                                .lineLimit(1)
                            Text(row.value)
                                .font(SharpitTypography.data)
                                .tracking(SharpitTypography.dataTracking)
                                .foregroundStyle(SharpitColor.foreground)
                                .monospacedDigit()
                            if let note = row.note {
                                Text(note)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !heartZones.isEmpty {
                ZoneDistribution(title: "Zones cardiaques", zones: heartZones)
            }
            if !powerZones.isEmpty {
                ZoneDistribution(title: "Zones de puissance", zones: powerZones)
            }
            if let line = ActivityTechnicalReadout.thresholdsLine(analysis) {
                Text(line)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

/// Time in each zone: one bar split by zone, then a line per zone with its share and time.
private struct ZoneDistribution: View {
    let title: String
    let zones: [V1ActivityAnalysis.Zone]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text(title)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                        if zone.percent > 0 {
                            Rectangle()
                                .fill(Self.tone(index))
                                .frame(width: max(2, (proxy.size.width - CGFloat(zones.count) * 2) * zone.percent / 100))
                        }
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            VStack(spacing: 6) {
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    HStack(spacing: SharpitSpacing.xs) {
                        Circle().fill(Self.tone(index)).frame(width: 7, height: 7)
                        Text(zone.shortLabel)
                            .font(SharpitTypography.meta.weight(.semibold))
                            .foregroundStyle(SharpitColor.foreground)
                            .frame(width: 28, alignment: .leading)
                        Text(zone.label)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(ActivityFormat.duration(zone.seconds))
                            .font(SharpitTypography.meta.monospacedDigit())
                            .foregroundStyle(SharpitColor.mutedForeground)
                        Text("\(Int(zone.percent.rounded())) %")
                            .font(SharpitTypography.meta.monospacedDigit().weight(.semibold))
                            .foregroundStyle(SharpitColor.foreground)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Easy to hard, in the app's intensity signals — the web's five chart tones.
    static func tone(_ index: Int) -> Color {
        [SharpitColor.signalRecovery, SharpitColor.signalBase, SharpitColor.signalTempo, SharpitColor.signalThreshold, SharpitColor.signalVo2][min(index, 4)]
    }
}
