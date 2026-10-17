import Foundation

/// The words and rules of Paramètres › Sports & équipement, kept apart from the views so what a
/// row says and when a sport can leave is decided once and tested (`docs/adr/0014`).
enum SportsReadout {
    /// What the athlete owns for one sport, on its row: a count, or what is left to fill in.
    /// Strength leads with where the athlete trains, since that decides what the list holds.
    static func equipmentSummary(
        sportId: String,
        owned: Set<String>,
        venue: V1AthleteEquipment.StrengthVenue
    ) -> String {
        let catalogIds = Set(
            PracticedSportCatalog.equipmentSports(for: [sportId])
                .flatMap { EquipmentCatalog.items(for: $0, venue: venue) }
                .map(\.id)
        )
        let count = catalogIds.intersection(owned).count
        let base: String
        if catalogIds.isEmpty {
            base = "Sans matériel particulier"
        } else if count == 0 {
            base = "Aucun matériel renseigné"
        } else {
            base = count == 1 ? "1 équipement" : "\(count) équipements"
        }
        return sportId == "strength" ? "\(venue.title) · \(base)" : base
    }

    /// A plan needs something to stand on: the sport that keeps the selection plannable stays.
    static func canRemove(_ sportId: String, from sports: Set<String>) -> Bool {
        PracticedSportCatalog.isPlannable(sports.subtracting([sportId]))
    }

    /// Sports not yet practiced, in catalog order — what the « + » sheet offers.
    static func addable(to sports: Set<String>) -> [PracticedSportItem] {
        PracticedSportCatalog.all.filter { !sports.contains($0.id) }
    }
}
