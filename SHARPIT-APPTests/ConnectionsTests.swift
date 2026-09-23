import CloudKit
import Foundation
import Testing
@testable import Sharpit

// MARK: - Garmin

@Test func garminBadgeIsReadFromTheProviderListNotAssumed() {
    let connected = V1SyncStatus(
        lastSyncAt: nil,
        providers: [V1SyncProvider(key: "garmin", label: "Garmin", lastSyncAt: nil)]
    )
    let withoutGarmin = V1SyncStatus(lastSyncAt: nil, providers: [])

    #expect(ConnectionsReadout.garmin(status: connected) == .init(text: "Connecté", tone: .positive))
    #expect(ConnectionsReadout.garmin(status: withoutGarmin) == .init(text: "Non connecté", tone: .neutral))
    #expect(ConnectionsReadout.garmin(status: nil) == .init(text: "—", tone: .neutral))
}

// MARK: - Apple Santé

/// The switch says on or off; the line only turns into a reason when the switch alone would mislead.
@Test func appleHealthSubtitleOnlyBecomesAReasonWhenSomethingStopsIt() {
    let normal = ConnectionsReadout.appleHealthSubtitle(isAvailable: true, state: .idle)
    let sending = ConnectionsReadout.appleHealthSubtitle(isAvailable: true, state: .sending)
    let unavailable = ConnectionsReadout.appleHealthSubtitle(isAvailable: false, state: .idle)
    let refused = ConnectionsReadout.appleHealthSubtitle(isAvailable: true, state: .failed("Accès refusé."))

    #expect(normal == .init(text: "Complète Garmin entre deux synchros", isProblem: false))
    #expect(sending == normal)
    #expect(unavailable == .init(text: "Indisponible sur cet iPhone", isProblem: false))
    #expect(refused == .init(text: "Accès refusé.", isProblem: true))
}

// MARK: - iCloud

@Test func everyICloudStatusHasAShortReading() {
    #expect(ConnectionsReadout.iCloud(.available) == "Actif")
    #expect(ConnectionsReadout.iCloud(.noAccount) == "Aucun compte")
    #expect(ConnectionsReadout.iCloud(.restricted) == "Restreint")
    #expect(ConnectionsReadout.iCloud(.temporarilyUnavailable) == "Indisponible")
    #expect(ConnectionsReadout.iCloud(.couldNotDetermine) == "Inconnu")
    #expect(ConnectionsReadout.iCloud(nil) == "—")
}
