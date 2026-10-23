import Foundation
import Testing
@testable import Sharpit

struct CoachQuickActionTests {
    @Test func weekAsksTagTheNextSevenDays() {
        for action in [CoachQuickAction.adjustWeek, .tiredOrHurt, .timeOff] {
            #expect(action.context(trainingDayId: "2026-10-23").target == .planning(horizonDays: 7))
        }
    }

    @Test func nutritionIsTaggedWithTheDayShown() {
        let context = CoachQuickAction.nutrition.context(trainingDayId: "2026-10-23")

        #expect(context.target == .nutrition(trainingDayId: "2026-10-23"))
    }

    @Test func everyActionOpensAnUnfinishedSentence() {
        for action in CoachQuickAction.allCases {
            #expect(!action.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(action.draft.last == " ")
        }
    }
}
