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

    @Test func aPickTagsTheConversationWithTheActionsOwnNameAndGlyph() {
        for action in CoachQuickAction.allCases {
            let context = action.context(trainingDayId: "2026-10-23")
            #expect(context.label == action.label)
            #expect(context.tagSymbol == action.symbol)
            #expect(context.prompt?.isEmpty == false)
        }
    }

    @Test func theLinesAboveTheBoxAreNeverRepeatedInThePlus() {
        let panel = CoachQuickAction.panel(showingSuggestions: true)
        #expect(panel == [.timeOff, .nutrition])
        #expect(Set(panel).isDisjoint(with: CoachQuickAction.suggested))
        #expect(CoachQuickAction.panel(showingSuggestions: false) == CoachQuickAction.allCases)
    }

    @Test func everyActionHasItsOwnGlyph() {
        let symbols = CoachQuickAction.allCases.map(\.symbol)
        #expect(Set(symbols).count == symbols.count)
    }
}
