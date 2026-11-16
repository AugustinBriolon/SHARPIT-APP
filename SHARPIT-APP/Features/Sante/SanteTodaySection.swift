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
    }

    var tiles: [Tile]

    init(tiles: [Tile]) { self.tiles = tiles }

    /// Nil when the day carries none of the three readings.
    init?(_ response: V1TodayResponse) {
        var tiles: [Tile] = []
        if let bank = response.energyBank, let value = bank.value {
            tiles.append(Tile(
                caption: String(localized: "Énergie"),
                value: "\(Int(value.rounded()))",
                unit: "/100",
                note: bank.typicalBaseline.map { String(localized: "D'habitude \(Int($0.rounded()))") },
                fraction: value / 100, pillar: .recovery, symbol: "bolt.fill"
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
                pillar: .nutrition, symbol: "flame.fill"
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

    static func statusLabel(_ status: String?) -> String? {
        switch status {
        case "below": String(localized: "Encore à faire")
        case "within": String(localized: "Atteint")
        case "above": String(localized: "Dépassé")
        default: nil
        }
    }
}

struct SanteTodaySection: View {
    let state: SanteDayState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SanteSectionTitle(String(localized: "Aujourd'hui"))
            CliniqueScoreStrip {
                ForEach(state.tiles, id: \.caption) { tile in
                    CliniqueScoreColumn(
                        pillar: tile.pillar, fraction: tile.fraction, symbol: tile.symbol,
                        title: tile.caption, value: tile.value, scale: tile.unit.map { String($0.dropFirst()) },
                        note: tile.note
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
