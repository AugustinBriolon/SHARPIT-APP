import Testing
@testable import Sharpit

@MainActor
@Suite struct SharpitToastCenterTests {
    /// A caller only clears the toast it put up — never one a later event already replaced
    /// it with, or the sync toast could eat the error toast that followed it.
    @Test func dismissOnlyClearsTheTokenThatShowedIt() {
        let center = SharpitToastCenter()
        let first = center.show("Synchronisation…", symbol: "arrow.triangle.2.circlepath", autoDismissAfter: nil)
        let second = center.show("Synchronisation impossible", symbol: "exclamationmark.triangle", tone: .error, autoDismissAfter: nil)

        center.dismiss(first)
        #expect(center.current?.id == second)

        center.dismiss(second)
        #expect(center.current == nil)
    }

    @Test func showingATwoReplacesTheFirstImmediately() {
        let center = SharpitToastCenter()
        center.show("Synchronisation…", symbol: "arrow.triangle.2.circlepath", autoDismissAfter: nil)
        center.show("Synchronisation impossible", symbol: "exclamationmark.triangle", tone: .error, autoDismissAfter: nil)

        #expect(center.current?.message == "Synchronisation impossible")
        #expect(center.current?.tone == .error)
    }

    @Test func dismissCurrentClearsWhoeverIsShowingRegardlessOfToken() {
        let center = SharpitToastCenter()
        center.show("Envoi vers Apple Santé…", symbol: "heart.text.square", autoDismissAfter: nil)

        center.dismissCurrent()

        #expect(center.current == nil)
    }
}
