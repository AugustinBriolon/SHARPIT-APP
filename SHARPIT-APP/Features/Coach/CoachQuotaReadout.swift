import Foundation

/// What the composer says about the coach budget. Nothing while more than half is left: the
/// gauge only shows once the athlete has something to plan around.
nonisolated enum CoachQuotaReadout {
    static func line(_ quota: V1CoachQuota, now: Date = .now) -> String? {
        if let wait = quota.retryAfterSeconds {
            return String(localized: "Plus d'échange pour l'instant · de nouveau \(eta(wait, now: now))")
        }
        guard quota.usedRatio >= 0.5 else { return nil }
        switch quota.remainingQuestions {
        case 0: return String(localized: "Moins d'un échange restant sur 24 h")
        case 1: return String(localized: "Environ 1 échange restant sur 24 h")
        case let count: return String(localized: "Environ \(count) échanges restants sur 24 h")
        }
    }

    /// Whether the budget is spent right now: the server's wait, counted from when it was read,
    /// has not run out. The composer will not send then — the server would refuse it.
    static func isSpent(_ quota: V1CoachQuota?, readAt: Date?, now: Date = .now) -> Bool {
        guard let wait = quota?.retryAfterSeconds, let readAt else { return false }
        return now < readAt.addingTimeInterval(TimeInterval(wait))
    }

    /// Free athletes are told Pro buys more, once the gauge shows.
    static func offersPro(_ quota: V1CoachQuota) -> Bool {
        !quota.isPro && line(quota) != nil
    }

    /// « 38 % » of the budget spent, for the Consommation sheet.
    static func usedPercent(_ quota: V1CoachQuota) -> String {
        "\(Int((min(max(quota.usedRatio, 0), 1) * 100).rounded())) %"
    }

    /// « 4 sur 6 » questions left — the web counts the token budget in questions (ADR-077).
    static func questionsLeft(_ quota: V1CoachQuota) -> String {
        "\(max(0, quota.remainingQuestions)) sur \(quota.dailyQuestions)"
    }

    /// When the budget comes back. The window is rolling, so there is no fixed reset date: only a
    /// spent budget has a time, the server's wait.
    static func resetLine(_ quota: V1CoachQuota, now: Date = .now) -> String {
        guard let wait = quota.retryAfterSeconds else {
            return String(localized: "Au fil de l'eau : chaque échange compte 24 h")
        }
        return String(localized: "De nouveau \(eta(wait, now: now))")
    }

    /// « dans 12 min », or the clock time past an hour: a relative wait goes stale on a screen
    /// left open, as the web's `formatBudgetRetryEta` says.
    static func eta(_ seconds: Int, now: Date = .now) -> String {
        if seconds < 3600 {
            return String(localized: "dans \(max(1, Int((Double(seconds) / 60).rounded(.up)))) min")
        }
        let time = now.addingTimeInterval(TimeInterval(seconds))
        return "à \(time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))"
    }
}
