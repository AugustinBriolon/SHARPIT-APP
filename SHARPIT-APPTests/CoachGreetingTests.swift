import Foundation
import Testing
@testable import Sharpit

private func at(hour: Int) -> (Date, Calendar) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: hour, minute: 30))!
    return (date, calendar)
}

private func greeting(hour: Int, firstName: String?) -> String {
    let (date, calendar) = at(hour: hour)
    return CoachGreeting.text(now: date, firstName: firstName, calendar: calendar)
}

@Test func theCoachGreetsByDayAndByEvening() {
    #expect(greeting(hour: 5, firstName: "Léa") == "Bonjour, Léa")
    #expect(greeting(hour: 17, firstName: "Léa") == "Bonjour, Léa")
    #expect(greeting(hour: 18, firstName: "Léa") == "Bonsoir, Léa")
    #expect(greeting(hour: 23, firstName: "Léa") == "Bonsoir, Léa")
    // Up in the night is still the evening before, not a morning.
    #expect(greeting(hour: 2, firstName: "Léa") == "Bonsoir, Léa")
}

@Test func withoutAFirstNameTheGreetingIsTheWordAlone() {
    #expect(greeting(hour: 9, firstName: nil) == "Bonjour")
    #expect(greeting(hour: 9, firstName: "  ") == "Bonjour")
    #expect(greeting(hour: 21, firstName: "") == "Bonsoir")
}
