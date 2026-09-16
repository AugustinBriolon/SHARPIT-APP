import Foundation

enum TodayArrivalPhase: Equatable {
    case hidden
    case plate
    case session
    case gauges
    case idle

    var showsPlate: Bool { self != .hidden }
    var showsSession: Bool {
        switch self {
        case .session, .gauges, .idle: true
        default: false
        }
    }
    var showsGauges: Bool {
        switch self {
        case .gauges, .idle: true
        default: false
        }
    }
}

@MainActor
enum TodayArrivalDirector {
    static func run(
        reduceMotion: Bool,
        gaugeCount: Int,
        update: @escaping (TodayArrivalPhase) -> Void
    ) async {
        if SharpitMotion.reduceMotion || reduceMotion {
            update(.idle)
            return
        }
        update(.plate)
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        update(.session)
        let gaugeDelay = SharpitMotion.staggerDelay(index: max(gaugeCount, 1))
        try? await Task.sleep(for: .seconds(gaugeDelay + 0.08))
        guard !Task.isCancelled else { return }
        update(.gauges)
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        update(.idle)
    }
}
