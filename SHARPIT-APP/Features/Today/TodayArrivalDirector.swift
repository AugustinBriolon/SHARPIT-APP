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
        // Three beats close together: the verdict, what to do, the scores. The rings then fill
        // on their own time; nothing else waits on them.
        update(.plate)
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }
        update(.session)
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else { return }
        update(.gauges)
        try? await Task.sleep(for: .seconds(SharpitMotion.arrivalDuration))
        guard !Task.isCancelled else { return }
        update(.idle)
    }
}
