import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// One thing the iPhone's search can find: its title, what it is and when, and the link that
/// opens it — the same `https://sharpit.app` links a notification or a widget opens.
/// Never a health figure: a title, a sport and a day only (the athlete's call, 2026-11-25).
nonisolated struct SpotlightEntry: Equatable, Sendable {
    enum Kind: String, Sendable { case plannedSession, activity, goal }

    let kind: Kind
    let id: String
    let title: String
    let detail: String
    let date: Date?
    let link: URL

    /// What the index holds under the athlete's search: the link, so a tap opens the page.
    var uniqueIdentifier: String { link.absoluteString }

    static func plannedSession(_ session: V1PlannedSessionItem) -> SpotlightEntry {
        let sport = session.type.flatMap(V1ActivityType.init(rawValue:))?.label
        return SpotlightEntry(
            kind: .plannedSession,
            id: session.id,
            title: session.title ?? sport ?? String(localized: "Séance prévue"),
            detail: [sport, String(localized: "Séance prévue")].compactMap { $0 }.joined(separator: " · "),
            date: session.date,
            link: WidgetSnapshot.link("/plan/session/\(session.id)")
        )
    }

    static func activity(_ activity: V1ActivityListItem) -> SpotlightEntry {
        SpotlightEntry(
            kind: .activity,
            id: activity.id,
            title: activity.title ?? activity.type.label,
            detail: [activity.type.label, String(localized: "Séance faite")].joined(separator: " · "),
            date: activity.date,
            link: WidgetSnapshot.link("/activity/\(activity.id)")
        )
    }

    static func goal(_ goal: V1Goal) -> SpotlightEntry {
        SpotlightEntry(
            kind: .goal,
            id: goal.id,
            title: goal.title,
            detail: String(localized: "Objectif"),
            date: nil,
            link: WidgetSnapshot.link("/goals")
        )
    }
}

/// The iPhone's search index for SharpIt. Each kind is replaced whole when its list is read, so a
/// session deleted or a goal removed leaves the search with it; the account's sign-out wipes it.
enum SpotlightIndex {
    /// How far ahead the plan is indexed: what the athlete would look for.
    static let planHorizonDays = 21
    /// The most recent sessions done, as the history's first page holds them.
    static let activityLimit = 60

    static func replace(_ kind: SpotlightEntry.Kind, with entries: [SpotlightEntry]) {
        Task.detached(priority: .utility) {
            let index = CSSearchableIndex.default()
            try? await index.deleteSearchableItems(withDomainIdentifiers: [kind.rawValue])
            try? await index.indexSearchableItems(entries.map(searchableItem))
        }
    }

    static func indexPlan(_ sessions: [V1PlannedSessionItem], now: Date = .now) {
        let horizon = Calendar.current.date(byAdding: .day, value: planHorizonDays, to: now) ?? now
        let start = Calendar.current.startOfDay(for: now)
        let ahead = sessions.filter { $0.date >= start && $0.date <= horizon && $0.completed != true }
        replace(.plannedSession, with: ahead.map(SpotlightEntry.plannedSession))
    }

    static func indexActivities(_ activities: [V1ActivityListItem]) {
        let recent = activities.sorted { $0.date > $1.date }.prefix(activityLimit)
        replace(.activity, with: recent.map(SpotlightEntry.activity))
    }

    static func indexGoals(_ goals: [V1Goal]) {
        replace(.goal, with: goals.filter { !$0.isReached }.map(SpotlightEntry.goal))
    }

    /// Another account on this iPhone must not find this one's sessions.
    static func eraseAll() {
        Task.detached(priority: .utility) {
            try? await CSSearchableIndex.default().deleteAllSearchableItems()
        }
    }

    nonisolated private static func searchableItem(_ entry: SpotlightEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.title
        attributes.contentDescription = entry.date.map {
            entry.detail + " · " + $0.formatted(.dateTime.weekday(.wide).day().month(.wide))
        } ?? entry.detail
        attributes.startDate = entry.date
        attributes.url = entry.link
        return CSSearchableItem(
            uniqueIdentifier: entry.uniqueIdentifier,
            domainIdentifier: entry.kind.rawValue,
            attributeSet: attributes
        )
    }
}

/// The link a search result opens: its identifier, which is the link it was indexed under.
nonisolated enum SpotlightLink {
    static func url(from userInfo: [AnyHashable: Any]?) -> URL? {
        (userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(URL.init(string:))
    }
}
