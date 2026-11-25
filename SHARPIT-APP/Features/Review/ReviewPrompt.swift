import Foundation
import StoreKit
import SwiftUI

/// When SharpIt may ask for an App Store rating: after a real win the screen already shows (a
/// full week, a goal reached, a strength session saved), never before the athlete has lived with
/// the app, at most once a version and never twice in four months. Apple decides whether its
/// window shows at all; SharpIt only decides when it may ask (the athlete's call, 2026-11-25).
nonisolated struct ReviewPromptPolicy: Equatable, Codable, Sendable {
    static let minimumDaysSinceFirstUse = 14
    static let minimumActiveDays = 3
    static let minimumDaysBetweenAsks = 120

    /// The first day the app was opened, as a calendar day.
    var firstUseDay: String?
    var lastActiveDay: String?
    var activeDayCount = 0
    var lastAskedAt: Date?
    var lastAskedVersion: String?

    /// The app opened on `now`: a new calendar day counts once.
    func recordingUse(on now: Date, calendar: Calendar = .current) -> ReviewPromptPolicy {
        let day = Self.dayId(now, calendar: calendar)
        guard day != lastActiveDay else { return self }
        var next = self
        next.firstUseDay = firstUseDay ?? day
        next.lastActiveDay = day
        next.activeDayCount += 1
        return next
    }

    func mayAsk(now: Date, version: String, calendar: Calendar = .current) -> Bool {
        guard let firstUseDay, let first = Self.date(firstUseDay, calendar: calendar),
              let daysSinceFirstUse = calendar.dateComponents([.day], from: first, to: now).day,
              daysSinceFirstUse >= Self.minimumDaysSinceFirstUse,
              activeDayCount >= Self.minimumActiveDays,
              lastAskedVersion != version
        else { return false }
        guard let lastAskedAt else { return true }
        let sinceLastAsk = calendar.dateComponents([.day], from: lastAskedAt, to: now).day ?? 0
        return sinceLastAsk >= Self.minimumDaysBetweenAsks
    }

    func asking(at now: Date, version: String) -> ReviewPromptPolicy {
        var next = self
        next.lastAskedAt = now
        next.lastAskedVersion = version
        return next
    }

    private static func dayId(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func date(_ dayId: String, calendar: Calendar) -> Date? {
        let parts = dayId.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// The policy kept on the iPhone, and the one place that asks.
@MainActor
enum ReviewPrompt {
    private static let storageKey = "sharpit.reviewPrompt"

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static func load(_ defaults: UserDefaults = .standard) -> ReviewPromptPolicy {
        defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(ReviewPromptPolicy.self, from: $0) } ?? ReviewPromptPolicy()
    }

    private static func save(_ policy: ReviewPromptPolicy, _ defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(policy), forKey: storageKey)
    }

    /// Called each time the app comes to the front.
    static func noteUse(defaults: UserDefaults = .standard, now: Date = .now) {
        save(load(defaults).recordingUse(on: now), defaults)
    }

    /// After a win: asks a moment later, once the screen has settled, if the policy allows.
    static func askAfterWin(_ requestReview: RequestReviewAction, defaults: UserDefaults = .standard) {
        let policy = load(defaults)
        guard policy.mayAsk(now: .now, version: version) else { return }
        save(policy.asking(at: .now, version: version), defaults)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            requestReview()
        }
    }

    /// Another account on this iPhone starts its own count.
    static func erase(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
