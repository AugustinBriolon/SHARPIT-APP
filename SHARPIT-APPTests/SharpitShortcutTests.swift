import Foundation
import Testing
@testable import Sharpit

private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

private let morning = paris.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 7))!

private func snapshot(dayId: String = "2026-12-03", verdict: Bool = true, sessions: [WidgetSnapshot.Session]) -> WidgetSnapshot {
    WidgetSnapshot(day: WidgetSnapshot.Day(
        trainingDayId: dayId,
        verdict: verdict ? WidgetSnapshot.Verdict(status: "Léger", headline: "Reste en endurance facile", action: nil, posture: .steady) : nil,
        sessions: sessions,
        sleep: nil
    ))
}

private let run = WidgetSnapshot.Session(id: "line-1", isDone: false, title: "Course · Seuil 40 min", sport: .run, plannedSessionId: "ps-1", figures: [])

@Test func siriSaysTheVerdictAndTheSessionOfToday() {
    #expect(SharpitShortcutReadout.verdict(snapshot: snapshot(sessions: [run]), now: morning, calendar: paris)
        == "Reste en endurance facile. Aujourd'hui : Course · Seuil 40 min.")
    var done = run
    done.isDone = true
    #expect(SharpitShortcutReadout.verdict(snapshot: snapshot(sessions: [done]), now: morning, calendar: paris)
        == "Reste en endurance facile. Séance faite : Course · Seuil 40 min.")
    #expect(SharpitShortcutReadout.verdict(snapshot: snapshot(sessions: []), now: morning, calendar: paris)
        == "Reste en endurance facile. Pas de séance prévue aujourd'hui.")
}

@Test func siriNeverSaysYesterdaysVerdict() {
    let yesterday = snapshot(dayId: "2026-12-02", sessions: [run])
    #expect(SharpitShortcutReadout.verdict(snapshot: yesterday, now: morning, calendar: paris) == "Ouvre SharpIt pour charger ta journée.")
    #expect(SharpitShortcutReadout.verdict(snapshot: nil, now: morning, calendar: paris) == "Ouvre SharpIt pour charger ta journée.")
    #expect(SharpitShortcutReadout.verdict(snapshot: snapshot(verdict: false, sessions: [run]), now: morning, calendar: paris)
        .hasPrefix("Ton verdict attend ta nuit"))
}

@Test func theSessionShortcutOpensTodaysSessionOrThePlan() {
    #expect(SharpitShortcutReadout.sessionLink(snapshot: snapshot(sessions: [run]), now: morning, calendar: paris)
        == URL(string: "https://sharpit.app/plan/session/ps-1"))
    #expect(SharpitShortcutReadout.sessionLink(snapshot: snapshot(dayId: "2026-12-02", sessions: [run]), now: morning, calendar: paris)
        == URL(string: "https://sharpit.app/plan"))
    // Every link a shortcut opens is one the app already reads.
    for path in ["/plan/session/ps-1", "/plan", "/nutrition/scan", "/coach"] {
        #expect(IncomingLink.parse(URL(string: "https://sharpit.app\(path)")!) != nil, "\(path)")
    }
}
