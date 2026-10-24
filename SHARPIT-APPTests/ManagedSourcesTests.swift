import Foundation
import Testing
@testable import Sharpit

// MARK: - Sources: connected list and « + »

@Test func connectedSourcesComeFirstAndTheRestAreOffered() {
    let lists = ConnectionsReadout.split(linked: [.strava, .appleHealth])

    #expect(lists.connected == [.appleHealth, .strava])
    #expect(lists.available == [.appleCalendar, .withings, .google, .garmin])
}

@Test func aSourceTheDeviceCannotRunIsNeverOffered() {
    let lists = ConnectionsReadout.split(linked: [], unavailable: [.appleHealth])

    #expect(!lists.available.contains(.appleHealth))
    #expect(lists.connected.isEmpty)
}

@Test func everySourceIsEitherConnectedOrOffered() {
    let lists = ConnectionsReadout.split(linked: [.withings])

    #expect(Set(lists.connected + lists.available) == Set(ManagedSource.allCases))
    #expect(lists.connected.count + lists.available.count == ManagedSource.allCases.count)
}

@Test func prioritiesOnlyMatterFromTwoConnectedSources() {
    #expect(!ConnectionsReadout.offersPriorities(connectedCount: 0))
    #expect(!ConnectionsReadout.offersPriorities(connectedCount: 1))
    #expect(ConnectionsReadout.offersPriorities(connectedCount: 2))
}

@Test func theOAuthSourcesKeepTheirDisconnectCopy() {
    #expect(ManagedSource.strava.oauth == .strava)
    #expect(ManagedSource.appleHealth.oauth == nil)
    #expect(ManagedSource.strava.disconnectMessage == DisconnectableSource.strava.confirmationMessage)
    #expect(ManagedSource.appleCalendar.disconnectTitle == "Déconnecter Calendrier Apple ?")
}
