import AppIntents
import Foundation

/// What Siri, Spotlight and the Shortcuts app can do with SharpIt without opening a menu
/// (the athlete's call, 2026-11-25). The phrases are French here and translated in
/// `AppShortcuts.xcstrings`, the catalog Siri reads them from. Each action lands on a page the app already opens from a
/// link (`IncomingLink`), so a shortcut never builds a route of its own.
struct SharpitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayVerdictIntent(),
            phrases: [
                "Mon verdict \(.applicationName)",
                "Quel est mon verdict \(.applicationName)",
            ],
            shortTitle: "Verdict du jour",
            systemImageName: "circle.hexagongrid"
        )
        AppShortcut(
            intent: OpenTodaySessionIntent(),
            phrases: [
                "Ma séance \(.applicationName)",
                "Ouvre ma séance \(.applicationName)",
            ],
            shortTitle: "Séance du jour",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Noter un repas dans \(.applicationName)",
                "Scanner un aliment avec \(.applicationName)",
            ],
            shortTitle: "Noter un repas",
            systemImageName: "barcode.viewfinder"
        )
        AppShortcut(
            intent: AskCoachIntent(),
            phrases: [
                "Demander au coach \(.applicationName)",
                "Parler au coach \(.applicationName)",
            ],
            shortTitle: "Demander au coach",
            systemImageName: "bubble.left"
        )
    }
}

/// The morning's verdict, said by Siri without opening the app: what Résumé's widget reads.
struct TodayVerdictIntent: AppIntent {
    static let title: LocalizedStringResource = "Verdict du jour"
    static let description = IntentDescription("Ce que SharpIt conseille aujourd'hui, et la séance prévue.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: SharpitShortcutReadout.verdict(snapshot: WidgetSnapshotStore.read(), now: .now)))
    }
}

struct OpenTodaySessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Séance du jour"
    static let description = IntentDescription("Ouvre la séance prévue aujourd'hui, ou ce que tu as fait.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharpitPageOpener.request(SharpitShortcutReadout.sessionLink(snapshot: WidgetSnapshotStore.read(), now: .now))
        return .result()
    }
}

struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Noter un repas"
    static let description = IntentDescription("Ouvre le scanner du journal alimentaire.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharpitPageOpener.request(WidgetSnapshot.link("/nutrition/scan"))
        return .result()
    }
}

struct AskCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Demander au coach"
    static let description = IntentDescription("Ouvre la conversation avec le coach.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharpitPageOpener.request(WidgetSnapshot.link("/coach"))
        return .result()
    }
}

/// What the shortcuts say and where they land, apart from App Intents so it can be tested.
nonisolated enum SharpitShortcutReadout {
    /// « Reste en endurance facile. Aujourd'hui : Course · Seuil 40 min. » — only from today's
    /// day: a day the app has not read yet is said as such, never yesterday's verdict.
    static func verdict(snapshot: WidgetSnapshot?, now: Date, calendar: Calendar = .current) -> String {
        guard let day = snapshot?.day(on: now, calendar: calendar) else {
            return String(localized: "Ouvre SharpIt pour charger ta journée.")
        }
        guard let verdict = day.verdict else {
            return String(localized: "Ton verdict attend ta nuit. Ouvre SharpIt une fois ta montre synchronisée.")
        }
        let headline = verdict.headline.hasSuffix(".") ? verdict.headline : verdict.headline + "."
        guard let session = day.leadSession else {
            return headline + " " + String(localized: "Pas de séance prévue aujourd'hui.")
        }
        return session.isDone
            ? headline + " " + String(localized: "Séance faite : \(session.title).")
            : headline + " " + String(localized: "Aujourd'hui : \(session.title).")
    }

    /// Today's session, done or to do; the plan when the day holds none or is not read yet.
    static func sessionLink(snapshot: WidgetSnapshot?, now: Date, calendar: Calendar = .current) -> URL {
        snapshot?.day(on: now, calendar: calendar)?.leadSession?.link ?? WidgetSnapshot.link("/plan")
    }
}
