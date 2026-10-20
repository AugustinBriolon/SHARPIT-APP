import Foundation
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

    @Test func triggerSetsUpDynamicNotificationWithTitleAndAvatar() {
        let center = SharpitToastCenter()
        var actionExecuted = false
        var dismissed = false

        let token = center.trigger(
            title: "Nouveau follower !",
            message: "Sasuke vous suit désormais",
            symbol: "person.fill.badge.plus",
            avatar: "https://example.com/avatar.jpg",
            duration: nil,
            action: { actionExecuted = true },
            onDismiss: { dismissed = true }
        )

        let current = center.current
        #expect(current?.id == token)
        #expect(current?.title == "Nouveau follower !")
        #expect(current?.message == "Sasuke vous suit désormais")
        #expect(current?.symbol == "person.fill.badge.plus")
        #expect(current?.avatarURL?.absoluteString == "https://example.com/avatar.jpg")
        #expect(current?.isDynamicNotification == true)

        current?.action?()
        #expect(actionExecuted == true)

        center.dismiss(token)
        #expect(center.current == nil)
        #expect(dismissed == true)
    }

    @Test func dismissCurrentInvokesOnDismiss() {
        let center = SharpitToastCenter()
        var dismissed = false

        center.trigger(
            title: "Info",
            duration: nil,
            onDismiss: { dismissed = true }
        )

        center.dismissCurrent()
        #expect(center.current == nil)
        #expect(dismissed == true)
    }

    @Test func regularToastIsNotMarkedAsDynamicNotification() {
        let center = SharpitToastCenter()
        center.show("Synchronisation…", symbol: "arrow.triangle.2.circlepath", autoDismissAfter: nil)

        #expect(center.current?.isDynamicNotification == false)
    }
}
