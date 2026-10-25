import Foundation
import Testing
@testable import Sharpit

private func day(_ id: String) -> Date { TrainingDayId.date(id)! }

@Suite struct SessionWatchPushTests {
    @Test func aSessionNeverSentIsNotOnTheWatch() {
        #expect(WatchPushState.of(garminWorkoutId: nil, scheduledDate: nil, sessionDate: day("2026-10-27")) == .notSent)
    }

    @Test func aSessionSentOnItsDayIsOnTheWatch() {
        #expect(WatchPushState.of(garminWorkoutId: "9001", scheduledDate: "2026-10-27", sessionDate: day("2026-10-27")) == .sent)
    }

    @Test func aSessionMovedAfterTheSendReadsAsMoved() {
        #expect(WatchPushState.of(garminWorkoutId: "9001", scheduledDate: "2026-10-27", sessionDate: day("2026-10-29")) == .moved)
    }

    @Test func onlyRunRideAndPoolGoToTheWatchForNow() {
        #expect(WatchPushState.canSend(type: "RUN"))
        #expect(WatchPushState.canSend(type: "bike"))
        #expect(WatchPushState.canSend(type: "SWIM"))
        #expect(!WatchPushState.canSend(type: "STRENGTH"))
        #expect(!WatchPushState.canSend(type: nil))
    }

    @Test func aMoveKeepsTheReceiptSoTheDrawerSaysMoved() {
        let sent = V1PlannedSessionItem(
            id: "s1",
            date: day("2026-10-27"),
            type: "RUN",
            garminWorkoutId: "9001",
            garminWorkoutScheduledDate: "2026-10-27"
        )
        var draft = PlannedSessionDraft(session: sent)
        draft.day = day("2026-10-29")
        let moved = sent.applying(draft)
        #expect(moved.garminWorkoutId == "9001")
        #expect(WatchPushState.of(
            garminWorkoutId: moved.garminWorkoutId,
            scheduledDate: moved.garminWorkoutScheduledDate,
            sessionDate: moved.date
        ) == .moved)
    }

    @Test func thePlannedSessionReadsItsGarminReceipt() throws {
        let json = Data("""
        {"id":"s1","date":"2026-10-27T00:00:00.000Z","garminWorkoutId":"9001","garminWorkoutScheduledDate":"2026-10-27"}
        """.utf8)
        let session = try JSONDecoder().decode(V1PlannedSessionItem.self, from: json)
        #expect(session.garminWorkoutId == "9001")
        #expect(session.garminWorkoutScheduledDate == "2026-10-27")
    }

    @Test func aGarminRefusalIsSaidInTheServersWordsNeverAsASignOut() {
        let permission = Data(#"{"error":"Reconnecte Garmin et autorise l’import d’entraînements.","code":"permission"}"#.utf8)
        #expect(GarminWorkoutClient.error(status: 403, body: permission) == .message("Reconnecte Garmin et autorise l’import d’entraînements."))
        #expect(GarminWorkoutClient.error(status: 403, body: Data(#"{"error":"pro_required"}"#.utf8)) == .proRequired)
        #expect(GarminWorkoutClient.error(status: 401, body: Data()) == .unauthorized)
        #expect(GarminWorkoutClient.error(status: 429, body: Data()) == .rateLimited)
        #expect(GarminWorkoutClient.error(status: 502, body: Data()) == .server)
    }

    @Test func aTargetSentWithoutGuidanceIsSaidAfterTheSend() {
        let plain = V1GarminWorkoutReceipt(workoutId: "1", scheduledDate: "2026-10-27", warnings: [], derived: false)
        #expect(SessionWatchContext.sentMessage(for: plain) == "Séance envoyée sur ta montre")
        let warned = V1GarminWorkoutReceipt(workoutId: "1", scheduledDate: "2026-10-27", warnings: ["FTP inconnue."], derived: false)
        #expect(SessionWatchContext.sentMessage(for: warned).hasSuffix("FTP inconnue."))
    }

    @Test func theMenuOffersASendThenAResend() {
        #expect(WatchPushState.notSent.menuTitle == "Envoyer sur ma montre")
        #expect(WatchPushState.sent.menuTitle == "Renvoyer sur ma montre")
        #expect(WatchPushState.moved.menuTitle == "Renvoyer sur ma montre")
        #expect(WatchPushState.notSent.symbolName == "applewatch")
        #expect(WatchPushState.sent.symbolName == "applewatch.and.arrow.forward")
    }

    @Test func theDrawerShowsNoMenuWhenItHasNothingToOffer() {
        #expect(SessionActionsMenu().isEmpty)
        #expect(!SessionActionsMenu(onLink: {}).isEmpty)
        #expect(!SessionActionsMenu(watch: SessionMenuAction(title: "Envoyer", symbolName: "paperplane") {}).isEmpty)
    }
}
