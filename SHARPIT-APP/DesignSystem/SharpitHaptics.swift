import CoreHaptics
import Foundation

/// The app's haptics, played through Core Haptics — a notch under the finger, and nothing else.
/// A tap, a choice, a success or a send is seen on screen; felt as well, it was noise.
///
/// Not `UIFeedbackGenerator`, nor SwiftUI's `sensoryFeedback` which rides on it: on the athlete's
/// iPhone neither played anything, anywhere in the app — the value under the height ruler changed
/// on every notch and nothing was felt — while a Core Haptics transient, fired the same way, was.
/// One engine, started on demand and restarted when the system stops or resets it.
enum SharpitHaptics {
    enum Kind {
        /// A notch passed under the finger — a ruler, painted days, a curve scrubbed; `major` on
        /// the tens.
        case notch(major: Bool)
    }

    static func play(_ kind: Kind) {
        switch kind {
        case .notch(let major): HapticEngine.shared.transient(intensity: major ? 1 : 0.7, sharpness: major ? 0.8 : 0.6)
        }
    }

    /// Starts the engine before a gesture, so the first notch is not late.
    static func prepare() {
        HapticEngine.shared.start()
    }
}

/// The shared Core Haptics engine. Transients only; silent where the hardware has none.
private final class HapticEngine {
    static let shared = HapticEngine()

    private let engine: CHHapticEngine?
    private var isRunning = false

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine()
        else {
            engine = nil
            return
        }
        engine.isAutoShutdownEnabled = true
        engine.playsHapticsOnly = true
        self.engine = engine
        engine.stoppedHandler = { [weak self] _ in self?.isRunning = false }
        engine.resetHandler = { [weak self] in
            self?.isRunning = false
            self?.start()
        }
    }

    func start() {
        guard let engine, !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func transient(intensity: Float, sharpness: Float) {
        guard let engine else { return }
        start()
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // Stopped between the check and the play: start again for the next one.
            isRunning = false
        }
    }
}
