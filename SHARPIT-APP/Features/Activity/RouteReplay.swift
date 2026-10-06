import Foundation
import Observation

/// The route drawn again from start to finish on the expanded map, played and paused at will.
/// Points are thinned evenly in time by the server, so a share of the points is a share of the
/// session: the line grows faster where the athlete went faster.
@Observable
final class RouteReplay {
    enum State: Equatable {
        case idle
        case playing
        case paused
        case finished
    }

    static let duration: TimeInterval = 12

    private(set) var state: State = .idle
    /// 0…1 while the route is being replayed; nil when the whole route is shown.
    private(set) var progress: Double?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Play from where it paused, pause while it plays, start again once it finished.
    func toggle() {
        switch state {
        case .playing: pause()
        case .paused: play()
        case .idle, .finished:
            progress = 0
            play()
        }
    }

    /// Back to the whole route, as when the map opened.
    func stop() {
        ticker?.cancel()
        ticker = nil
        state = .idle
        progress = nil
    }

    private func pause() {
        ticker?.cancel()
        ticker = nil
        state = .paused
    }

    private func play() {
        state = .playing
        ticker?.cancel()
        ticker = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, !Task.isCancelled else { return }
                let now = ContinuousClock.now
                let elapsed = (now - last) / .seconds(1)
                last = now
                let next = (self.progress ?? 0) + elapsed / Self.duration
                if next >= 1 {
                    self.progress = nil
                    self.state = .finished
                    self.ticker = nil
                    return
                }
                self.progress = next
            }
        }
    }
}

/// The part of the route already replayed.
nonisolated enum RouteReplayPath {
    /// The first `progress` share of the path, its last point placed between two recorded ones
    /// so the line grows smoothly rather than point by point.
    static func prefix(_ path: [V1ActivityCoordinate], progress: Double) -> [V1ActivityCoordinate] {
        guard path.count >= 2 else { return path }
        let position = min(max(progress, 0), 1) * Double(path.count - 1)
        let whole = Int(position)
        var result = Array(path[0...whole])
        let fraction = position - Double(whole)
        if whole < path.count - 1, fraction > 0 {
            result.append(interpolate(path[whole], path[whole + 1], fraction))
        }
        return result
    }

    /// The same share of a route cut into intensity stretches. Each stretch starts on the last
    /// point of the one before (`RouteIntensity`), so the route has one point fewer per joint.
    static func prefix(_ segments: [RouteIntensity.Segment], progress: Double) -> [RouteIntensity.Segment] {
        let total = segments.reduce(1) { $0 + max($1.coordinates.count - 1, 0) }
        guard total >= 2 else { return segments }
        let position = min(max(progress, 0), 1) * Double(total - 1)
        var result: [RouteIntensity.Segment] = []
        var start = 0
        for segment in segments {
            let end = start + max(segment.coordinates.count - 1, 0)
            if position >= Double(end) {
                result.append(segment)
            } else {
                if position > Double(start) {
                    let share = (position - Double(start)) / Double(end - start)
                    result.append(RouteIntensity.Segment(
                        level: segment.level,
                        coordinates: prefix(segment.coordinates, progress: share)
                    ))
                }
                break
            }
            start = end
        }
        return result
    }

    private static func interpolate(
        _ from: V1ActivityCoordinate,
        _ to: V1ActivityCoordinate,
        _ fraction: Double
    ) -> V1ActivityCoordinate {
        V1ActivityCoordinate(
            latitude: from.latitude + (to.latitude - from.latitude) * fraction,
            longitude: from.longitude + (to.longitude - from.longitude) * fraction
        )
    }
}
