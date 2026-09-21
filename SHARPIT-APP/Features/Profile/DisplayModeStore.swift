import Foundation
import Observation
import SwiftUI

/// The reading density, for every surface that shows a technical figure (ADR 0006).
///
/// Its own store rather than reaching for `AthleteProfileStore`: the density is read far from
/// any profile screen — on an activity, in the planned session drawer — and those surfaces
/// have no business knowing a profile exists. It holds one bool and the fact that the profile
/// has not answered yet.
@MainActor
@Observable
final class DisplayModeStore {
    /// Essential until the profile says otherwise. A technical number that flashes in and
    /// then disappears reads worse than one arriving a moment late.
    private(set) var isExpert = false
    /// False until the profile has answered once, so a surface can wait rather than guess.
    private(set) var isResolved = false

    private let client: any AthleteProfileServing

    init(client: any AthleteProfileServing) {
        self.client = client
    }

    /// Reads the density once. The token is passed in rather than held: the store is built
    /// alongside the tab view, before the closure that produces a Clerk token exists.
    ///
    /// Silent on failure — a screen that cannot learn the density renders the essential one,
    /// which is the default anyway.
    func load(tokenProvider: () async throws -> String) async {
        guard !isResolved else { return }
        guard let token = try? await tokenProvider(),
              let profile = try? await client.athleteProfile(token: token) else { return }
        isExpert = profile.isExpertReading
        isResolved = true
    }

    /// Adopts a density decided elsewhere — the picker in Moi saves through
    /// `AthleteProfileStore` and tells this store what the profile now holds.
    func adopt(isExpert: Bool) {
        self.isExpert = isExpert
        isResolved = true
    }
}

private struct DisplayModeKey: EnvironmentKey {
    @MainActor static let defaultValue: DisplayModeStore? = nil
}

extension EnvironmentValues {
    /// Nil where no store was injected — a preview, or a test rendering one view. A surface
    /// reads `isExpertReading` rather than this, so a missing store means essential.
    var displayMode: DisplayModeStore? {
        get { self[DisplayModeKey.self] }
        set { self[DisplayModeKey.self] = newValue }
    }

    /// What a surface asks: is the athlete reading the technical layer?
    var isExpertReading: Bool {
        self[DisplayModeKey.self]?.isExpert ?? false
    }
}
