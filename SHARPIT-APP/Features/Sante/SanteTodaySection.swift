import SwiftUI

/// Santé's « Aujourd'hui »: Energy Bank, stress and the target strain band (ADR-079), read from
/// GET /api/v1/today. Moved here from Résumé's « État du jour » strip.
struct SanteDayState: Equatable {
    struct Tile: Equatable {
        var caption: String
        var value: String
        var unit: String?
        var note: String?
        /// The ring: how full, in which pillar's hue, around which glyph.
        var fraction: Double?
        var pillar: CliniquePillar
        var symbol: String
        /// Where the athlete usually stands, 0…1: a tick on the gauge.
        var baseline: Double? = nil
        /// Read as a status rather than on a gauge — the target band, reached or not.
        var status: CliniqueStatus? = nil
    }

    var tiles: [Tile]

    init(tiles: [Tile]) { self.tiles = tiles }

    /// The section's shape while the day is read: its three lines with stand-in figures, drawn
    /// redacted — never grey blocks of guessed sizes.
    static let placeholder = SanteDayState(tiles: [
        Tile(caption: String(localized: "Énergie"), value: "00", unit: "/100", note: "D'habitude 00",
             fraction: 0, pillar: .recovery, symbol: "bolt.fill"),
        Tile(caption: String(localized: "Stress"), value: "00", unit: "/100", note: "Calme",
             fraction: 0, pillar: .sleep, symbol: "waveform.path.ecg"),
        Tile(caption: String(localized: "Effort visé"), value: "00–00", unit: nil, note: "Encore à faire",
             fraction: 0, pillar: .nutrition, symbol: "flame.fill", status: .unknown),
    ])

    /// Nil when the day carries none of the three readings.
    init?(_ response: V1TodayResponse) {
        var tiles: [Tile] = []
        if let bank = response.energyBank, let value = bank.value {
            tiles.append(Tile(
                caption: String(localized: "Énergie"),
                value: "\(Int(value.rounded()))",
                unit: "/100",
                note: bank.typicalBaseline.map { String(localized: "D'habitude \(Int($0.rounded()))") },
                fraction: value / 100, pillar: .recovery, symbol: "bolt.fill",
                baseline: bank.typicalBaseline.map { $0 / 100 }
            ))
        }
        if let stress = response.stress {
            tiles.append(Tile(
                caption: String(localized: "Stress"),
                value: "\(Int(stress.value.rounded()))",
                unit: "/100",
                note: Self.stressCaption(stress.value),
                fraction: stress.value / 100, pillar: .sleep, symbol: "waveform.path.ecg"
            ))
        }
        if let band = response.targetBand {
            tiles.append(Tile(
                caption: String(localized: "Effort visé"),
                value: String(format: "%.0f–%.0f", band.low, band.high),
                unit: nil,
                note: Self.statusLabel(band.status),
                // The day's strain is not in the payload: the ring closes once the band is reached.
                fraction: band.status == "within" || band.status == "above" ? 1 : 0,
                pillar: .nutrition, symbol: "flame.fill",
                status: Self.bandStatus(band.status)
            ))
        }
        guard !tiles.isEmpty else { return nil }
        self.tiles = tiles
    }

    static func stressCaption(_ value: Double) -> String {
        if value >= 75 { return String(localized: "Élevé") }
        if value >= 50 { return String(localized: "Modéré") }
        return String(localized: "Calme")
    }

    static func bandStatus(_ status: String?) -> CliniqueStatus {
        switch status {
        case "within": .good
        case "above": .watch
        default: .unknown
        }
    }

    static func statusLabel(_ status: String?) -> String? {
        switch status {
        case "below": String(localized: "Encore à faire")
        case "within": String(localized: "Atteint")
        case "above": String(localized: "Dépassé")
        default: nil
        }
    }
}

/// The day's readings as lines, each on its gauge: the hero above already reads as rings, and
/// the same rings twice made one section look like the other (the athlete's call, 2026-11-16).
struct SanteTodaySection: View {
    let state: SanteDayState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SanteSectionTitle(String(localized: "Aujourd'hui"))
            ForEach(Array(state.tiles.enumerated()), id: \.element.caption) { index, tile in
                if index > 0 { CliniqueDivider() }
                SanteTodayLine(tile: tile)
                    .padding(.vertical, SharpitSpacing.sm)
                    .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct SanteTodayLine: View {
    let tile: SanteDayState.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tile.pillar.color)
                    .frame(width: 20, alignment: .leading)
                    .accessibilityHidden(true)
                Text(tile.caption)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(tile.value)
                        .font(SharpitTypography.system(size: 20, weight: .semibold, relativeTo: .title3, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                    if let unit = tile.unit {
                        Text(unit)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
            }
            if let status = tile.status, let note = tile.note {
                CliniqueStatusPill(note, status: status)
                    .padding(.leading, 28)
            } else {
                if let fraction = tile.fraction {
                    SanteGauge(fraction: fraction, baseline: tile.baseline, tint: tile.pillar.color)
                        .padding(.leading, 28)
                }
                if let note = tile.note {
                    Text(note)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .padding(.leading, 28)
                }
            }
        }
    }
}

/// A reading on its scale: how far it stands, and a tick where it usually does. The bar fills
/// from empty when the section is drawn and to each new reading after — the one thing in the
/// section that moves (`SharpitMotion.gaugeFill`, instant under Reduce Motion).
private struct SanteGauge: View {
    let fraction: Double
    let baseline: Double?
    let tint: Color

    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(SharpitColor.tile)
                Capsule().fill(tint).frame(width: max(6, width * shown))
                if let baseline {
                    Capsule()
                        .fill(SharpitColor.foreground)
                        .frame(width: 2, height: 12)
                        .offset(x: width * min(max(baseline, 0), 1) - 1)
                }
            }
        }
        .frame(height: 6)
        .padding(.vertical, 3)
        .onAppear { fill(to: fraction) }
        .onChange(of: fraction) { _, new in fill(to: new) }
        .accessibilityHidden(true)
    }

    private func fill(to fraction: Double) {
        SharpitMotion.run(SharpitMotion.gaugeFill) {
            shown = min(max(fraction, 0), 1)
        }
    }
}
