import Foundation

/// What the composer says about the coach budget. Nothing while more than half is left: the
/// gauge only shows once the athlete has something to plan around.
nonisolated enum CoachQuotaReadout {
    static func line(_ quota: V1CoachQuota, now: Date = .now) -> String? {
        if let wait = quota.retryAfterSeconds {
            return "Plus d'échange pour l'instant · de nouveau \(eta(wait, now: now))"
        }
        guard quota.usedRatio >= 0.5 else { return nil }
        switch quota.remainingQuestions {
        case 0: return "Moins d'un échange restant sur 24 h"
        case 1: return "Environ 1 échange restant sur 24 h"
        case let count: return "Environ \(count) échanges restants sur 24 h"
        }
    }

    /// Free athletes are told Pro buys more, once the gauge shows.
    static func offersPro(_ quota: V1CoachQuota) -> Bool {
        !quota.isPro && line(quota) != nil
    }

    /// « dans 12 min », or the clock time past an hour: a relative wait goes stale on a screen
    /// left open, as the web's `formatBudgetRetryEta` says.
    static func eta(_ seconds: Int, now: Date = .now) -> String {
        if seconds < 3600 {
            return "dans \(max(1, Int((Double(seconds) / 60).rounded(.up)))) min"
        }
        let time = now.addingTimeInterval(TimeInterval(seconds))
        return "à \(time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))"
    }
}
