import Foundation
import Testing
@testable import Sharpit

@MainActor
struct ShellRouterRevisionTests {
    /// A session recorded from the phone must reach Plan (it reloads on `calendarRevision`),
    /// Activité (`activitiesRevision`) and Résumé, even when their week or day is already loaded.
    @Test func anActivityRecordedTellsEveryScreenToReadAgain() {
        let router = ShellRouter()

        router.noteActivitiesChanged()

        #expect(router.calendarRevision == 1)
        #expect(router.activitiesRevision == 1)
    }
}
