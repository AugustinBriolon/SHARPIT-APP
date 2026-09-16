import Foundation

/// Local anti-spam for instrument-grade win moments (once per day / session).
enum SharpitWinStore {
    private static var defaults: UserDefaults { .standard }

    static func consume(_ key: String) -> Bool {
        if defaults.bool(forKey: key) { return false }
        defaults.set(true, forKey: key)
        return true
    }

    static func arrivalKey(trainingDayId: String) -> String {
        "sharpit.win.arrival.\(trainingDayId)"
    }

    static func sessionDoneKey(trainingDayId: String, sessionId: String) -> String {
        "sharpit.win.sessionDone.\(trainingDayId).\(sessionId)"
    }

    static func lastConfidence(trainingDayId: String) -> Int? {
        let key = confidenceKey(trainingDayId: trainingDayId)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    static func setLastConfidence(_ value: Int, trainingDayId: String) {
        defaults.set(value, forKey: confidenceKey(trainingDayId: trainingDayId))
    }

    private static func confidenceKey(trainingDayId: String) -> String {
        "sharpit.win.confidence.\(trainingDayId)"
    }

    #if DEBUG
    static func resetForTests() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("sharpit.win.") {
            defaults.removeObject(forKey: key)
        }
    }
    #endif
}
