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
    /// Nutrition to open on the barcode scanner, once — the « Scanner un produit » widget.
    var pendingFoodScan = false

    func openFoodScan() {
        pendingFoodScan = true
        selectedTab = .today
    }

    func openActivity(id: String) {
        pendingActivityId = id
        selectedTab = .activity
    }

    func openPlannedSession(id: String) {
        pendingPlannedSessionId = id
        selectedTab = .plan
    }

    /// Bumped when the calendar changed elsewhere than on Plan — a coach proposal carried out —
    /// so Plan and Résumé reload what they show.
    private(set) var calendarRevision = 0

    func noteCalendarChanged() {
        calendarRevision += 1
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
        switch destination {
        case .tab(let tab):
            select(tab)
        case .planGenerator:
            select(.plan)
            isShowingPlanGenerator = true
        case .weeklyReview:
            select(.plan)
            isShowingWeeklyReview = true
        case .goals:
            select(.plan)
            isShowingGoals = true
        case .settings(let route):
            openSettings(on: route)
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
}

enum ShellTab: Hashable, CaseIterable {
    case today
    case plan
    case coach
    case activity
    case body
}
