import Foundation

/// Local switch for BLE heart-rate during guided strength (App Group, default off).
nonisolated enum GuidedHeartRatePreference {
    static let key = "guidedStrengthHeartRateBLE"

    private static var suite: UserDefaults {
        UserDefaults(suiteName: "group.app.sharpit.ios") ?? .standard
    }

    static var isEnabled: Bool {
        suite.bool(forKey: key)
    }

    static func setEnabled(_ on: Bool) {
        suite.set(on, forKey: key)
    }

    /// Sign-out / account wipe — drop the switch and the last peripheral id.
    static func clear() {
        suite.removeObject(forKey: key)
        suite.removeObject(forKey: lastPeripheralKey)
    }

    /// Last successfully connected HR peripheral — used to reconnect without a full scan UI.
    static var lastPeripheralUUID: UUID? {
        get {
            guard let raw = suite.string(forKey: lastPeripheralKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            suite.set(newValue?.uuidString, forKey: lastPeripheralKey)
        }
    }

    private static let lastPeripheralKey = "guidedStrengthHeartRatePeripheralId"
}
