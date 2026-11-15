import ClerkKit
import Testing
@testable import Sharpit

/// App Review signs in on a device Clerk has never seen: only that status asks for the e-mailed second factor.
@Test func onlyAnUnknownDeviceAsksForTheClientTrustCode() {
    #expect(SignIn.Status(rawValue: "needs_client_trust").awaitsClientTrustCode)
    for status: SignIn.Status in [.complete, .needsFirstFactor, .needsSecondFactor, .needsIdentifier] {
        #expect(!status.awaitsClientTrustCode)
    }
}
