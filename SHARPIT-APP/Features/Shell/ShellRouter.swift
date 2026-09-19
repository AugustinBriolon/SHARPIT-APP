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

    func select(_ tab: ShellTab) {
        selectedTab = tab
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

enum ShellTab: Hashable, CaseIterable {
    case today
    case plan
    case coach
    case activity
    case me
}
