import CoreHaptics
import Foundation

/// The app's haptics, played through Core Haptics.
///
/// Not `UIFeedbackGenerator`, nor SwiftUI's `sensoryFeedback` which rides on it: on the athlete's
/// iPhone neither played anything, anywhere in the app — the value under the height ruler changed
/// on every notch and nothing was felt — while a Core Haptics transient, fired the same way, was.
/// One engine, started on demand and restarted when the system stops or resets it.
enum SharpitHaptics {
    enum Kind {
        case soft
        case light
        case success
        /// A notch passed under the finger on a ruler; `major` on the tens.
        case notch(major: Bool)
    }

    static func play(_ kind: Kind) {
        switch kind {
        case .soft: HapticEngine.shared.transient(intensity: 0.45, sharpness: 0.2)
        case .light: HapticEngine.shared.transient(intensity: 0.6, sharpness: 0.5)
        case .notch(let major): HapticEngine.shared.transient(intensity: major ? 1 : 0.7, sharpness: major ? 0.8 : 0.6)
        case .success:
            HapticEngine.shared.transient(intensity: 0.7, sharpness: 0.5)
            HapticEngine.shared.transient(intensity: 1, sharpness: 0.6, delay: 0.12)
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

    func transient(intensity: Float, sharpness: Float, delay: TimeInterval = 0) {
        guard let engine else { return }
        start()
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: delay
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
