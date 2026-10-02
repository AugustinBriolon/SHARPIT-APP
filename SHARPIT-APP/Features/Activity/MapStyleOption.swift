import MapKit
import SwiftUI

/// The activity map's base layer, picked from the expanded map's layers menu.
enum MapStyleOption: String, CaseIterable, Identifiable, Sendable {
    case standard = "Plan"
    case imagery = "Satellite"
    case hybrid = "Mixte"

    var id: String { rawValue }

    var mapStyle: MapStyle {
        switch self {
        case .standard:
            return .standard(elevation: .realistic)
        case .imagery:
            return .imagery(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        }
    }
}
