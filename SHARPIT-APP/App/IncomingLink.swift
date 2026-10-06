import Foundation
import Observation

/// What an opened URL asks the app to do.
///
/// Only `https://sharpit.app` is honoured: it is the one host in the Associated Domains, so a
/// link on any other host — `api.`, `web.`, or a look-alike — is not ours to act on. The
/// custom scheme belongs to Clerk's OAuth redirects and is not a navigation link.
enum IncomingLink: Equatable {
    case garminCallback(status: String?)
    case tab(ShellTab)
    /// Paramètres, on one of its pages when the path names it.
    case settings(SettingsRoute?)
    /// A recorded activity — a done session tapped in a widget.
    case activity(id: String)
    /// A planned session, opened in Plan's drawer — a session to do tapped in a widget.
    case plannedSession(id: String)
    /// Plan's Objectifs — the next race tapped in a widget.
    case goals
    /// Résumé on one of its pages — the day itself (the verdict widget), Sommeil, Nutrition, or
    /// Nutrition on the barcode scanner (the « Scanner un produit » widget or control).
    case today(TodayPage)

    nonisolated static let trustedHost = "sharpit.app"

    nonisolated static func parse(_ url: URL) -> IncomingLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme == "https",
              components.host == trustedHost
        else { return nil }

        if components.path == "/connect/garmin/callback" {
            let status = components.queryItems?.first(where: { $0.name == "garmin" })?.value
            return .garminCallback(status: status)
        }
        if components.path == "/settings" {
            return .settings(nil)
        }
        if components.path == "/settings/sources" {
            return .settings(.sources)
        }
        // A locked widget's tap: the offer it names. A hidden one's: the switch that hid it.
        if components.path == "/settings/pro" {
            return .settings(.pro)
        }
        if components.path == "/settings/features" {
            return .settings(.features)
        }
        if components.path == "/goals" {
            return .goals
        }
        if let page = todayPage(forPath: components.path) {
            return .today(page)
        }
        if let id = identifier(in: components.path, after: "/activity/") {
            return .activity(id: id)
        }
        if let id = identifier(in: components.path, after: "/plan/session/") {
            return .plannedSession(id: id)
        }
        return tab(forPath: components.path).map(IncomingLink.tab)
    }

    /// The Résumé pages a widget opens. Sommeil and Nutrition are pushed from Résumé, so they
    /// are asked of it rather than being tabs of their own.
    nonisolated static func todayPage(forPath path: String) -> TodayPage? {
        switch path {
        case "/today": .overview
        case "/sleep", "/today/sleep": .sleep
        case "/nutrition": .nutrition
        case "/nutrition/scan": .foodScan
        default: nil
        }
    }

    /// The id a path ends with after `prefix`, when there is exactly one.
    nonisolated private static func identifier(in path: String, after prefix: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let id = String(path.dropFirst(prefix.count))
        return id.isEmpty || id.contains("/") ? nil : id
    }

    /// The tab a web path stands for — shared with the push payloads' `url`.
    nonisolated static func tab(forPath path: String) -> ShellTab? {
        switch path {
        case "/today": .today
        case "/plan": .plan
        case "/coach": .coach
        case "/activity", "/activities": .activity
        // Moi became Corps; its old links land there.
        case "/body", "/corps", "/me", "/profile": .body
        default: nil
        }
    }
}

/// Links opened before the tabs exist wait here. A widget tapped on a cold launch delivers its
/// URL while the gates still check the session and the account, before `RootView` is on screen
/// to hear it — so the app takes every URL and `RootView` empties the inbox once it shows.
@Observable
@MainActor
final class IncomingLinkInbox {
    private(set) var pending: URL?

    func receive(_ url: URL) {
        guard IncomingLink.parse(url) != nil else { return }
        pending = url
    }

    func take() -> URL? {
        defer { pending = nil }
        return pending
    }
}
