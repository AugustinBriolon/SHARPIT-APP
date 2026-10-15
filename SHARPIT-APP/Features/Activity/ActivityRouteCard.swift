import Foundation

/// Distance / durée / allure (or vitesse) for the « Dernière activité » widget.
nonisolated struct ActivityRouteStats: Equatable, Sendable {
    struct Figure: Equatable, Sendable {
        var value: String
        var unit: String
        var spoken: String {
            [value, unit].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    let distance: Figure
    let duration: Figure
    let paceLabel: String
    let pace: Figure

    init(_ activity: V1ActivityListItem) {
        if let meters = activity.distanceM, meters > 0 {
            if meters >= 1_000 {
                distance = Figure(
                    value: String(format: "%.2f", meters / 1_000).replacingOccurrences(of: ".", with: ","),
                    unit: "km"
                )
            } else {
                distance = Figure(value: "\(Int(meters.rounded()))", unit: "m")
            }
        } else {
            distance = Figure(value: "", unit: "")
        }

        if let seconds = activity.duration, seconds > 0 {
            duration = Figure(value: Self.clock(seconds), unit: "min")
        } else {
            duration = Figure(value: "", unit: "")
        }

        if activity.type == .bike,
           let meters = activity.distanceM, meters > 0,
           let seconds = activity.duration, seconds > 0 {
            paceLabel = "Vitesse"
            pace = Figure(value: Self.speedKmh(distanceM: meters, duration: seconds), unit: "km/h")
        } else if activity.type == .swim,
                  let meters = activity.distanceM, meters > 0,
                  let seconds = activity.duration, seconds > 0 {
            paceLabel = "Allure"
            pace = Figure(value: Self.paceClock(seconds / (meters / 100)), unit: "/100 m")
        } else if let meters = activity.distanceM, meters >= 100,
                  let seconds = activity.duration, seconds > 0 {
            paceLabel = "Allure"
            pace = Figure(value: Self.paceClock(seconds / (meters / 1_000)), unit: "/km")
        } else {
            paceLabel = "Allure"
            pace = Figure(value: "", unit: "")
        }
    }

    /// « 28:14 » under an hour, « 1:05:00 » above.
    private static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", secs))"
        }
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    private static func speedKmh(distanceM: Double, duration: Double) -> String {
        guard duration > 0 else { return "" }
        return String(format: "%.1f", distanceM / duration * 3.6).replacingOccurrences(of: ".", with: ",")
    }

    /// « 5:25 » — colon form, as on the map-card reference.
    private static func paceClock(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        return "\(rounded / 60):\(String(format: "%02d", rounded % 60))"
    }
}
