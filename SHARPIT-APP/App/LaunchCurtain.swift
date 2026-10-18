import Foundation
import Observation

/// The cold launch's one loading screen: up from the first frame until the screen the athlete
/// lands on can be drawn whole, so Résumé never shows its own loading shape on launch.
///
/// It lifts once something has said « ready » (Résumé's read answered; the sign-in, the legal
/// wall, the wizard or another tab shown instead) and the mark
/// has been seen for `minimum` — a lift any sooner reads as a flicker. Past `timeout` it lifts
/// whatever the network is doing: a slow or failed read then shows on Résumé itself.
@MainActor
@Observable
final class LaunchCurtain {
    static let minimum: Duration = .milliseconds(600)
    static let timeout: Duration = .milliseconds(3500)

    private(set) var isUp = true

    @ObservationIgnored private var isReady = false
    @ObservationIgnored private var hasShownMinimum = false
    @ObservationIgnored private var hasTimedOut = false
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let lift: (_ body: () -> Void) -> Void

    /// `lift` wraps the change that removes the curtain, so the view animates its exit.
    init(lift: @escaping (_ body: () -> Void) -> Void = { $0() }) {
        self.lift = lift
    }

    /// Starts the two clocks; a second call does nothing.
    func run(minimum: Duration = LaunchCurtain.minimum, timeout: Duration = LaunchCurtain.timeout) async {
        guard !isRunning else { return }
        isRunning = true
        // A cancelled wait (the scene gone) ends at once and lifts: never a curtain left up.
        try? await Task.sleep(for: minimum)
        minimumElapsed()
        try? await Task.sleep(for: max(timeout - minimum, .zero))
        timedOut()
    }

    func markReady() {
        isReady = true
        liftIfDue()
    }

    func minimumElapsed() {
        hasShownMinimum = true
        liftIfDue()
    }

    func timedOut() {
        hasTimedOut = true
        liftIfDue()
    }

    private func liftIfDue() {
        guard isUp, hasTimedOut || (isReady && hasShownMinimum) else { return }
        lift { isUp = false }
    }
}
