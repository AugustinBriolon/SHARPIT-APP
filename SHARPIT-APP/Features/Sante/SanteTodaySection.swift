import SwiftUI

/// Santé's « Aujourd'hui »: Energy Bank, stress and the target strain band (ADR-079), read from
/// GET /api/v1/today. Moved here from Résumé's « État du jour » strip.
struct SanteDayState: Equatable {
    struct Tile: Equatable {
        var caption: String
        var value: String
        var unit: String?
        var note: String?
    }

    var tiles: [Tile]

    /// Nil when the day carries none of the three readings.
    init?(_ response: V1TodayResponse) {
        var tiles: [Tile] = []
        if let bank = response.energyBank, let value = bank.value {
            tiles.append(Tile(
                caption: "Énergie",
                value: "\(Int(value.rounded()))",
                unit: "/100",
                note: bank.typicalBaseline.map { "D'habitude \(Int($0.rounded()))" }
            ))
        }
        if let stress = response.stress {
            tiles.append(Tile(
                caption: "Stress",
                value: "\(Int(stress.value.rounded()))",
                unit: "/100",
                note: Self.stressCaption(stress.value)
            ))
        }
        if let band = response.targetBand {
            tiles.append(Tile(
                caption: "Effort visé",
                value: String(format: "%.0f–%.0f", band.low, band.high),
                unit: nil,
                note: Self.statusLabel(band.status)
            ))
        }
        guard !tiles.isEmpty else { return nil }
        self.tiles = tiles
    }

    static func stressCaption(_ value: Double) -> String {
        if value >= 75 { return "Élevé" }
        if value >= 50 { return "Modéré" }
        return "Calme"
    }

    static func statusLabel(_ status: String?) -> String? {
        switch status {
        case "below": "Encore à faire"
        case "within": "Atteint"
        case "above": "Dépassé"
        default: nil
        }
    }
}

struct SanteTodaySection: View {
    let state: SanteDayState

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Aujourd'hui")
            HStack(spacing: SharpitSpacing.sm) {
                ForEach(state.tiles, id: \.caption) { tile in
                    SharpitStatTile(caption: tile.caption, value: tile.value, unit: tile.unit, note: tile.note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
