import Foundation
import Testing
@testable import Sharpit

/// When a food was eaten (SHARPIT ADR-137): only a time the athlete stands behind is sent.
@Suite struct FoodEatenTimeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: hour, minute: minute))!
    }

    @Test func theMealOfTheHourLoggedTodayOpensOnNowAndIsSent() {
        let time = FoodEatenTime.initial(meal: .lunch, trainingDayId: "2026-11-19", now: date(12, 47), calendar: calendar)
        #expect(time.minute == 12 * 60 + 47)
        #expect(time.sent == 12 * 60 + 47)
    }

    @Test func anotherMealOpensOnItsUsualHourAndIsNotSent() {
        // Breakfast logged in the evening: the clock says nothing about when it was eaten.
        let time = FoodEatenTime.initial(meal: .breakfast, trainingDayId: "2026-11-19", now: date(21, 5), calendar: calendar)
        #expect(time.minute == 8 * 60)
        #expect(time.sent == nil)
    }

    @Test func anotherDayIsNeverNow() {
        let time = FoodEatenTime.initial(meal: .dinner, trainingDayId: "2026-11-18", now: date(19, 40), calendar: calendar)
        #expect(time.minute == 19 * 60 + 30)
        #expect(time.sent == nil)
    }

    @Test func aTimeSetByHandIsSentAndSurvivesAMealChange() {
        var time = FoodEatenTime.initial(meal: .breakfast, trainingDayId: "2026-11-19", now: date(21, 5), calendar: calendar)
        time.minute = 7 * 60 + 15
        time.isSet = true
        time.follow(meal: .snacks, trainingDayId: "2026-11-19", now: date(21, 5), calendar: calendar)
        #expect(time.sent == 7 * 60 + 15)
    }

    @Test func anUntouchedTimeFollowsTheMeal() {
        var time = FoodEatenTime.initial(meal: .breakfast, trainingDayId: "2026-11-19", now: date(21, 5), calendar: calendar)
        time.follow(meal: .dinner, trainingDayId: "2026-11-19", now: date(21, 5), calendar: calendar)
        #expect(time.minute == 21 * 60 + 5)
        #expect(time.sent == 21 * 60 + 5)
    }

    @Test func readsAsTheClock() {
        #expect(FoodEatenTime.clock(7 * 60 + 5) == "07:05")
        #expect(FoodEatenTime.clock(23 * 60 + 59) == "23:59")
    }

    @Test func theDraftSendsItsTimeOnlyWhenItHasOne() throws {
        let product = V1FoodProduct(
            id: "p1", source: "OFF", barcode: nil, name: "Riz", brand: nil,
            kcalPer100g: 350, proteinPer100g: 7.5, carbsPer100g: 77, fatPer100g: 1,
            fiberPer100g: nil, sugarPer100g: nil, servingGrams: nil, servingLabel: nil
        )
        var draft = FoodLogDraft(trainingDayId: "2026-11-19", meal: .lunch, grams: 150, source: .product(product))
        #expect(FoodLogClient.payload(for: draft)["eatenMinute"] == nil)
        draft.eatenMinute = 12 * 60 + 40
        #expect(FoodLogClient.payload(for: draft)["eatenMinute"] as? Int == 12 * 60 + 40)
        #expect(FoodLogStore.pendingEntry(for: draft).eatenMinute == 12 * 60 + 40)
    }

    @Test func anEntryChangeCarriesANewTime() throws {
        let data = try FoodLogClient.body(for: FoodLogEntryChange(grams: nil, meal: nil, eatenMinute: 10 * 60))
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body.keys.sorted() == ["eatenMinute"])
        #expect(body["eatenMinute"] as? Int == 600)
    }

    @Test func anEntryDecodesItsTime() throws {
        let json = #"{"id":"e1","meal":"SNACKS","name":"Banane","grams":120,"kcal":107,"protein":1.3,"carbs":27,"fat":0.4,"eatenMinute":615}"#
        let entry = try JSONDecoder().decode(V1FoodLogEntry.self, from: Data(json.utf8))
        #expect(entry.eatenMinute == 615)
        #expect(FoodEatenTime.existing(entry).sent == 615)
    }
}
