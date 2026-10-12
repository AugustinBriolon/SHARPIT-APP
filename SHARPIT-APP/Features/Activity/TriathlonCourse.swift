import Foundation

/// What the triathlon page reads: the whole course, or one leg of it.
nonisolated enum TriathlonSelection: Hashable, Sendable {
    case overview
    /// A leg by its segment id — its place among the timed legs.
    case leg(Int)
}

/// One leg of the course as the page draws it: its stretch of the route and its samples, the
/// time rebased to the leg's start.
nonisolated struct TriathlonLegTrack: Sendable, Equatable, Identifiable {
    let id: Int
    let leg: V1MultisportLeg
    let segment: RaceLegSegment
    let route: [V1ActivityCoordinate]
    let samples: [V1ActivityStreamSample]
    /// The leg's own technical reading, when its own recording came with one.
    let analysis: V1ActivityAnalysis?
}

nonisolated enum TriathlonCourse {
    /// Below this share of the race, the parent's recording does not cover every leg and is not sliced.
    static let minimumCoverage = 0.9

    /// Each timed leg with the best data at hand: its own recording when the server cached one,
    /// else its share of the parent's (the parent's path and samples are thinned evenly in time,
    /// so a time window maps to the same share of each). A transition without GPS of its own is
    /// drawn from the leg before it to the leg after it.
    static func tracks(
        legs: [V1MultisportLeg],
        parent: V1ActivityStreamPayload?,
        legStreams: [V1MultisportLegStream]
    ) -> [TriathlonLegTrack] {
        let timed = legs.filter { $0.durationSec > 0 }
        let total = timed.reduce(0) { $0 + $1.durationSec }
        let slicer = ParentSlicer(parent, raceSeconds: total)
        var start = 0.0
        let tracks = zip(timed, RaceLegsTimeline.segments(legs)).map { leg, segment in
            let window = start...(start + leg.durationSec)
            start += leg.durationSec
            let own = legStreams.first { $0.leg.id == leg.id }?.stream
            let ownRoute = own?.route ?? []
            let ownSamples = own?.samples ?? []
            return TriathlonLegTrack(
                id: segment.id,
                leg: leg,
                segment: segment,
                route: ownRoute.isEmpty ? slicer?.route(in: window) ?? [] : ownRoute,
                samples: ownSamples.isEmpty ? slicer?.samples(in: window) ?? [] : ownSamples,
                analysis: own?.analysis
            )
        }
        return bridgingTransitions(tracks)
    }

    /// « Tout », then each leg in race order: « Natation · T1 · Vélo · T2 · Course ».
    static func options(_ tracks: [TriathlonLegTrack]) -> [(value: TriathlonSelection, label: String)] {
        [(.overview, "Tout")] + tracks.map { (.leg($0.id), $0.segment.label) }
    }

    static func track(for selection: TriathlonSelection, in tracks: [TriathlonLegTrack]) -> TriathlonLegTrack? {
        guard case .leg(let id) = selection else { return nil }
        return tracks.first { $0.id == id }
    }

    /// What the camera frames: the whole course, or the leg; empty for a leg without GPS, which
    /// leaves the camera where it is.
    static func route(for selection: TriathlonSelection, in tracks: [TriathlonLegTrack]) -> [V1ActivityCoordinate] {
        switch selection {
        case .overview: tracks.flatMap(\.route)
        case .leg: track(for: selection, in: tracks)?.route ?? []
        }
    }

    private static func bridgingTransitions(_ tracks: [TriathlonLegTrack]) -> [TriathlonLegTrack] {
        tracks.enumerated().map { index, track in
            guard track.segment.isTransition, track.route.count < 2,
                  let before = tracks[safe: index - 1]?.route.last,
                  let after = tracks[safe: index + 1]?.route.first
            else { return track }
            return TriathlonLegTrack(
                id: track.id, leg: track.leg, segment: track.segment,
                route: [before, after], samples: track.samples, analysis: track.analysis
            )
        }
    }
}

/// The parent's recording cut by time, when it covers the race.
private nonisolated struct ParentSlicer {
    let path: [V1ActivityCoordinate]
    let samples: [V1ActivityStreamSample]
    let recordedSeconds: Double

    init?(_ parent: V1ActivityStreamPayload?, raceSeconds: Double) {
        guard let parent, raceSeconds > 0 else { return nil }
        let samples = parent.samples.sorted { $0.t < $1.t }
        let recorded = samples.last?.t ?? 0
        guard recorded >= raceSeconds * TriathlonCourse.minimumCoverage else { return nil }
        self.path = parent.route
        self.samples = samples
        self.recordedSeconds = recorded
    }

    /// Both ends kept, so consecutive legs meet on the map.
    func route(in window: ClosedRange<Double>) -> [V1ActivityCoordinate] {
        guard path.count > 1 else { return [] }
        let last = Double(path.count - 1)
        let from = Int((window.lowerBound / recordedSeconds * last).rounded(.down))
        let to = Int((window.upperBound / recordedSeconds * last).rounded(.up))
        let lower = min(max(from, 0), path.count - 1)
        let upper = min(max(to, lower), path.count - 1)
        return Array(path[lower...upper])
    }

    func samples(in window: ClosedRange<Double>) -> [V1ActivityStreamSample] {
        let inside = samples.filter { window.contains($0.t) }
        guard let first = inside.first else { return [] }
        return inside.map {
            V1ActivityStreamSample(
                t: $0.t - window.lowerBound, d: max(0, $0.d - first.d), alt: $0.alt, hr: $0.hr,
                watts: $0.watts, cadence: $0.cadence, speed: $0.speed
            )
        }
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
