import AVFoundation
import Observation
import Speech

/// What the composer's one round button does, from what the athlete has on hand.
///
/// One control, four meanings, never two buttons: an empty field offers the microphone, words
/// offer to send, listening offers to stop, and while the coach answers the button waits.
enum CoachComposerAction: Equatable {
    case dictate
    case stopDictation
    case send
    case waiting

    init(isReplying: Bool, isDictating: Bool, draft: String) {
        if isReplying {
            self = .waiting
        } else if isDictating {
            self = .stopDictation
        } else if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self = .dictate
        } else {
            self = .send
        }
    }

    var symbol: String {
        switch self {
        case .dictate: "mic"
        case .stopDictation: "waveform"
        case .send: "arrow.up"
        case .waiting: "stop.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .dictate: "Dicter un message"
        case .stopDictation: "Arrêter la dictée"
        case .send: "Envoyer"
        case .waiting: "Le coach répond"
        }
    }

    /// Filled with the brand colour when it is the way forward: sending, or listening.
    var isProminent: Bool { self == .send || self == .stopDictation }
}

/// Dictation into the coach's composer, in French, on the device when it can.
///
/// The words heard are written into the draft as they come, after what was already typed, and
/// the athlete sends them as they would typed ones. Nothing is recorded or kept.
@MainActor
@Observable
final class CoachDictation {
    private(set) var isListening = false
    /// Why dictation cannot start, in words the athlete can act on.
    private(set) var failure: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// The draft once dictation has added `heard` after what was typed before it.
    nonisolated static func merged(typed: String, heard: String) -> String {
        let base = typed.trimmingCharacters(in: .whitespaces)
        let words = heard.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return typed }
        return base.isEmpty ? words : "\(base) \(words)"
    }

    /// Starts listening; `onText` receives the draft rewritten with what has been heard so far.
    func start(typed: String, onText: @escaping @MainActor (String) -> Void) async {
        guard !isListening else { return }
        failure = nil
        guard await Self.authorized() else {
            failure = "Autorise le micro et la reconnaissance vocale dans Réglages pour dicter."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            failure = "La dictée n'est pas disponible pour le moment."
            return
        }
        do {
            try begin(with: recognizer, typed: typed, onText: onText)
            isListening = true
        } catch {
            stop()
            failure = "La dictée n'a pas pu démarrer."
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func begin(
        with recognizer: SFSpeechRecognizer,
        typed: String,
        onText: @escaping @MainActor (String) -> Void
    ) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No microphone (a simulator without one) reports a zero rate, and tapping it crashes.
        guard format.sampleRate > 0 else { throw DictationUnavailable() }
        Self.feed(request, from: input, format: format)
        audioEngine.prepare()
        try audioEngine.start()

        task = Self.recognize(request, with: recognizer) { [weak self] heard, finished in
            Task { @MainActor in
                if let heard { onText(Self.merged(typed: typed, heard: heard)) }
                if finished { self?.stop() }
            }
        }
    }

    private struct DictationUnavailable: Error {}

    // The audio and speech frameworks call back on their own queues. Written inside this
    // main-actor class, those closures would be main-actor isolated and trap when called
    // there, so they are built in nonisolated functions.

    nonisolated private static func feed(
        _ request: SFSpeechAudioBufferRecognitionRequest,
        from input: AVAudioInputNode,
        format: AVAudioFormat
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(
        _ request: SFSpeechAudioBufferRecognitionRequest,
        with recognizer: SFSpeechRecognizer,
        onResult: @escaping @Sendable (_ heard: String?, _ finished: Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onResult(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
        }
    }

    nonisolated private static func authorized() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
