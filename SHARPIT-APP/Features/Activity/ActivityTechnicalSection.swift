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
        let locale = AppLanguage.locale
        func decimal(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        }

        if let power = analysis.power, let normalized = power.normalized {
            rows.append(ActivityTechnicalRow(
                label: "NP",
                value: "\(Int(normalized.rounded())) W",
                note: power.avg.map { String(localized: "moy \(Int($0.rounded())) W") }
            ))
        }
        if let intensityFactor = analysis.load?.intensityFactor {
            rows.append(ActivityTechnicalRow(label: "IF", value: decimal(intensityFactor), note: intensityReference(analysis)))
        }
        if let variability = analysis.power?.variabilityIndex {
            rows.append(ActivityTechnicalRow(
                label: "VI",
                value: decimal(variability),
                note: variability > 1.1 ? String(localized: "effort variable") : String(localized: "effort régulier")
            ))
        }
        if let tss = analysis.load?.tss {
            rows.append(ActivityTechnicalRow(label: analysis.load?.method == "hr" ? "TSS (FC)" : "TSS", value: "\(Int(tss.rounded()))"))
        }
        if let efficiency = analysis.hr?.efficiencyFactor {
            rows.append(ActivityTechnicalRow(
                label: analysis.hr?.efficiencyLabel ?? String(localized: "Facteur d'efficacité"),
                value: efficiency.formatted(.number.locale(locale))
            ))
        }
        if let decoupling = analysis.hr?.decouplingPct {
            let sign = decoupling > 0 ? "+" : ""
            rows.append(ActivityTechnicalRow(
                label: String(localized: "Découplage"),
                value: "\(sign)\(decoupling.formatted(.number.precision(.fractionLength(0...1)).locale(locale))) %",
                note: decouplingNote(abs(decoupling))
            ))
        }
        if let paceVariability = analysis.run?.paceVariabilityPct {
            rows.append(ActivityTechnicalRow(
                label: String(localized: "Variabilité allure"),
                value: "\(paceVariability.formatted(.number.precision(.fractionLength(0...1)).locale(locale))) %",
                note: String(localized: "écart-type / moyenne")
            ))
        }
        return rows
    }

    /// « FTP 250 W · LTHR 168 bpm · estimés » — the references the figures were read against.
    static func thresholdsLine(_ analysis: V1ActivityAnalysis) -> String? {
        guard let thresholds = analysis.thresholds else { return nil }
        let parts = [
            thresholds.ftp.map { "FTP \(Int($0.rounded())) W" },
            thresholds.lthr.map { String(localized: "LTHR \(Int($0.rounded())) bpm") },
            thresholds.maxHr.map { String(localized: "FC max \(Int($0.rounded())) bpm") },
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        let origin = thresholds.source == "estimate" ? String(localized: "seuils estimés") : String(localized: "seuils du profil")
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
        return analysis.thresholds?.lthr.map { String(localized: "LTHR \(Int($0.rounded())) bpm") }
    }

    static func decouplingNote(_ magnitude: Double) -> String {
        if magnitude < 5 { return String(localized: "Peu de dérive cardiaque") }
        if magnitude < 10 { return String(localized: "Correct pour une sortie longue") }
        return String(localized: "Dérive élevée : chaleur, fatigue ou endurance")
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
            SharpitEyebrow.title(String(localized: "Analyse technique"))
            if !rows.isEmpty {
                ActivityTechnicalGrid(rows: rows)
            }
            if !heartZones.isEmpty {
                ZoneDistribution(title: String(localized: "Zones cardiaques"), zones: heartZones)
            }
            if !powerZones.isEmpty {
                ZoneDistribution(title: String(localized: "Zones de puissance"), zones: powerZones)
            }
            if let line = ActivityTechnicalReadout.thresholdsLine(analysis) {
                Text(line)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Figures two by two: a label, the value, and what it says.
struct ActivityTechnicalGrid: View {
    let rows: [ActivityTechnicalRow]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: SharpitSpacing.md, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
            alignment: .leading,
            spacing: SharpitSpacing.md
        ) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(1)
                    Text(row.value)
                        .font(SharpitTypography.system(size: 19, weight: .semibold, relativeTo: .title3, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                    if let note = row.note {
                        Text(note)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Time in each zone, a line per zone as the mock-up draws it: its name, its range over a gauge
/// filled to its share in the zone's hue, then its time.
private struct ZoneDistribution: View {
    let title: String
    let zones: [V1ActivityAnalysis.Zone]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                .foregroundStyle(SharpitColor.foreground)
                .padding(.bottom, SharpitSpacing.xs)
            ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                HStack(spacing: 10) {
                    Text(zone.shortLabel)
                        .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(width: 30, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(zone.label)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                            .lineLimit(1)
                        SharpitBarTrack(fraction: zone.percent / 100, tone: SharpitZoneTone.color(index))
                            .frame(height: 6)
                    }
                    Text(ActivityFormat.duration(zone.seconds))
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(width: 62, alignment: .trailing)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(zone.shortLabel), \(zone.label), \(ActivityFormat.duration(zone.seconds)), \(Int(zone.percent.rounded())) %")
                if index < zones.count - 1 { CliniqueDivider() }
            }
        }
    }
}
