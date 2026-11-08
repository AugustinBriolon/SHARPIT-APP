import Foundation
import Testing
@testable import Sharpit

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
    return calendar
}()

@Test func anInstantParsesWithOrWithoutFractionalSeconds() {
    let withFraction = APIDate.instant("2026-11-07T12:00:00.250Z")
    let withoutFraction = APIDate.instant("2026-11-07T12:00:00Z")
    #expect(withFraction != nil)
    #expect(withoutFraction == Date(timeIntervalSince1970: withFraction!.timeIntervalSince1970.rounded(.down)))
}

@Test func anInstantWritesWithMilliseconds() {
    let date = Date(timeIntervalSince1970: 1_799_000_000.5)
    #expect(APIDate.string(from: date).hasSuffix(".500Z"))
    #expect(APIDate.instant(APIDate.string(from: date)) == date)
}

@Test func aDayIsReadAtItsMidnightInTheGivenZone() throws {
    let utcDay = try #require(APIDate.day("2026-11-07", calendar: APIDate.utcCalendar))
    #expect(APIDate.utcCalendar.component(.hour, from: utcDay) == 0)
    #expect(APIDate.utcCalendar.component(.day, from: utcDay) == 7)

    let parisDay = try #require(APIDate.day("2026-11-07", calendar: paris))
    #expect(paris.component(.day, from: parisDay) == 7)
    #expect(paris.component(.hour, from: parisDay) == 0)
}

@Test func aDayRoundTripsAndAnUnreadableDayIsNil() throws {
    let day = try #require(APIDate.day("2026-03-29", calendar: paris))
    #expect(APIDate.dayString(day, calendar: paris) == "2026-03-29")
    #expect(APIDate.day("not a day", calendar: paris) == nil)
    #expect(APIDate.instant("soon") == nil)
}

@Test func aNonPositionalFormatCannotBeMistakenForADay() {
    #expect(APIDate.day("2026-11-07T12:00:00Z", calendar: paris) == nil)
}
