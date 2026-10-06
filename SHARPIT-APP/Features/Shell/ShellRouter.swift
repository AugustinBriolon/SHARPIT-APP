import Foundation
import Observation

/// Cross-tab navigation for the shell.
///
/// A surface that sends the athlete elsewhere — the regularity strip opening Plan, a
/// "Discuter avec le coach" button — states the destination here rather than reaching
/// into another feature. The tabs stay independent; the router is the only shared state.
@Observable
@MainActor
final class ShellRouter {
    var selectedTab: ShellTab = .today

    /// Set when the athlete asks to discuss something, read by the Coach tab when it
    /// appears. It is a tag the conversation carries, never a prefilled prompt: the
    /// athlete writes their own question, the coach is told what they were looking at.
    private(set) var pendingCoachContext: CoachDiscussContext?

    /// Paramètres is a sheet over the tabs, opened from the avatar in Résumé and Corps or a
    /// `/settings` link — not a tab: the athlete tunes it rarely and leaves it at once.
    var isShowingSettings = false
    /// The page Paramètres opens on — a notification about a source opens Sources de données.
    private(set) var settingsRoute: SettingsRoute?

    /// Plan's « Remplir ma semaine » sheet — here so a notification can open it.
    var isShowingPlanGenerator = false

    /// Plan's « Bilan de la semaine » sheet — here so « Ton bilan est prêt » can open it.
    var isShowingWeeklyReview = false

    /// Plan's Objectifs sheet — here so the « Prochain objectif » widget can open it.
    var isShowingGoals = false

    /// An activity to open in Activité, once — a done session tapped in a widget.
    var pendingActivityId: String?
    /// A planned session to open in Plan's drawer, once — a session to do tapped in a widget.
    var pendingPlannedSessionId: String?
    /// A missed session to catch up on in Plan, once — « Dommage pour hier » tapped.
    var pendingCatchUp: PlanCatchUp?
    /// A page of Résumé to show, once — a widget tapped: the day itself, Sommeil, Nutrition or
    /// its barcode scanner.
    var pendingTodayPage: TodayPage?

    /// Résumé on one of its pages. Paramètres is closed first: a widget tapped while it was up
    /// would otherwise open its page behind the sheet.
    func openToday(_ page: TodayPage) {
        isShowingSettings = false
        pendingTodayPage = page
        selectedTab = .today
    }

    func openActivity(id: String) {
        isShowingSettings = false
        pendingActivityId = id
        selectedTab = .activity
    }

    func openPlannedSession(id: String) {
        isShowingSettings = false
        pendingPlannedSessionId = id
        selectedTab = .plan
    }

    /// Bumped when the calendar changed elsewhere than on Plan — a coach proposal carried out —
    /// so Plan and Résumé reload what they show.
    private(set) var calendarRevision = 0

    func noteCalendarChanged() {
        calendarRevision += 1
    }

    /// Bumped when an activity was logged, edited or deleted by hand, so Activité reads its list
    /// again — the plan too, since the server links a session to what it counts for.
    private(set) var activitiesRevision = 0

    func noteActivitiesChanged() {
        activitiesRevision += 1
        calendarRevision += 1
    }

    /// Bumped once a morning check-in reached the server, which then read the night against
    /// today's session — Résumé reads the day again to show the proposal it may have made.
    private(set) var checkInRevision = 0

    func noteMorningCheckIn() {
        checkInRevision += 1
    }

    func select(_ tab: ShellTab) {
        selectedTab = tab
    }

    func openSettings(on route: SettingsRoute? = nil) {
        settingsRoute = route
        isShowingSettings = true
    }

    /// Opens what a notification points at.
    func open(_ destination: NotificationDestination) {
        // Paramètres sits over every tab: left up, it would hide the page asked for.
        let settingsWasUp = isShowingSettings
        if case .settings = destination {} else { isShowingSettings = false }
        switch destination {
        case .tab(let tab):
            select(tab)
        case .planGenerator:
            select(.plan)
            present(after: settingsWasUp) { $0.isShowingPlanGenerator = true }
        case .weeklyReview:
            select(.plan)
            present(after: settingsWasUp) { $0.isShowingWeeklyReview = true }
        case .goals:
            select(.plan)
            present(after: settingsWasUp) { $0.isShowingGoals = true }
        case .settings(let route):
            openSettings(on: route)
        case .activity(let id):
            openActivity(id: id)
        case .catchUp(let label, let day):
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
            let catchUp = PlanCatchUp(label: label, date: TrainingDayId.date(day) ?? yesterday)
            select(.plan)
            present(after: settingsWasUp) { $0.pendingCatchUp = catchUp }
        }
    }

    /// A sheet asked for while Paramètres was going down is shown once it is gone: UIKit refuses
    /// a presentation while another sheet is still leaving.
    private func present(after settingsWasUp: Bool, _ show: @escaping @MainActor (ShellRouter) -> Void) {
        guard settingsWasUp else { return show(self) }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self else { return }
            show(self)
        }
    }

    /// Opens Coach carrying what the athlete was looking at.
    func discussWithCoach(about context: CoachDiscussContext) {
        pendingCoachContext = context
        selectedTab = .coach
    }

    /// Called by Coach once it has taken the context, so returning to the tab later does
    /// not silently re-attach a stale subject.
    func consumeCoachContext() -> CoachDiscussContext? {
        defer { pendingCoachContext = nil }
        return pendingCoachContext
    }
}

/// Where a tapped notification leads.
enum NotificationDestination: Equatable {
    case tab(ShellTab)
    case planGenerator
    case weeklyReview
    case goals
    case settings(SettingsRoute?)
    case activity(id: String)
    /// A missed session, by the label the coach is told and its training day.
    case catchUp(label: String, day: String)
}

/// What a link asks Résumé to show.
nonisolated enum TodayPage: Equatable, Sendable {
    /// The day itself, with nothing pushed over it.
    case overview
    case sleep
    case nutrition
    /// Nutrition with the barcode scanner up.
    case foodScan
}

enum ShellTab: Hashable, CaseIterable {
    case today
    case plan
    case coach
    case activity
    case body
}
