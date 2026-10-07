import Foundation

/// Local switch for the coach-reply Live Activity (App Group, default on).
nonisolated enum CoachReplyLiveActivityPreference {
    static let key = "coachReplyLiveActivity"

    private static var suite: UserDefaults {
        UserDefaults(suiteName: "group.app.sharpit.ios") ?? .standard
    }

    static var isEnabled: Bool {
        if suite.object(forKey: key) == nil { return true }
        return suite.bool(forKey: key)
    }

    static func setEnabled(_ on: Bool) {
        suite.set(on, forKey: key)
    }
}
