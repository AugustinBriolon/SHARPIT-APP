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

@Suite struct SharpitBannerDismissTests {
    @Test func upwardDragPastFortyPercentDismisses() {
        #expect(SharpitBannerDismiss.shouldDismiss(height: 50, translationY: -20, velocityY: 0))
        #expect(!SharpitBannerDismiss.shouldDismiss(height: 50, translationY: -10, velocityY: 0))
    }

    @Test func fastUpwardFlickDismissesEvenWhenShort() {
        #expect(SharpitBannerDismiss.shouldDismiss(height: 80, translationY: -8, velocityY: -950))
    }

    @Test func downwardDragIsRubberBandedAndDoesNotDismiss() {
        let offset = SharpitBannerDismiss.offset(translationY: 30, height: 60)
        #expect(offset > 0)
        #expect(offset < 30)
        #expect(!SharpitBannerDismiss.shouldDismiss(height: 60, translationY: 30, velocityY: 400))
    }
}
