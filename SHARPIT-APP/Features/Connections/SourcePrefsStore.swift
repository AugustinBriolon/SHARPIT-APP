import Foundation
import Observation

/// Which sources feed each data class and which is the primary (SHARPIT ADR-054), changed with
/// the tap: the choice shows at once and goes out behind (`SharpitRetry`); a change the web refuses
/// or that fails for good is said in the app's toast, and the page reads the web's prefs again.
@MainActor
@Observable
final class SourcePrefsStore {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var prefs = V1SourcePrefs(classes: [:])
    private(set) var connected: [String] = []
    /// The classes where a choice exists: at least one connected provider can feed them.
    private(set) var classes: [V1SourceClass] = []

    private let client: any SourcePrefsServing
    private let tokenProvider: () async throws -> String
    private let failures: SharpitWriteFailures
    /// Writes still out: an echo only lands when no newer tap is waiting on its own.
    @ObservationIgnored private var pendingWrites = 0

    init(
        client: any SourcePrefsServing,
        tokenProvider: @escaping () async throws -> String,
        failures: SharpitWriteFailures = .shared
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.failures = failures
    }

    func load() async {
        do {
            let answer = try await SharpitRetry.run {
                try await client.sourcePrefs(token: try await tokenProvider())
            }
            connected = answer.connected
            classes = answer.classes.filter { sourceClass in
                sourceClass.providers.contains { answer.connected.contains($0.id) }
            }
            prefs = answer.prefs
            phase = .loaded
        } catch {
            if phase != .loaded { phase = .failed("Lecture de tes sources impossible.") }
        }
    }

    func isConnected(_ provider: String) -> Bool { connected.contains(provider) }

    func isEnabled(_ provider: String, in classId: String) -> Bool {
        prefs.sources(for: classId).enabled.contains(provider)
    }

    func isPrimary(_ provider: String, in classId: String) -> Bool {
        prefs.sources(for: classId).primary == provider
    }

    /// Connected providers listed for this class (from the last GET).
    func connectedCount(in classId: String) -> Int {
        classes.first(where: { $0.id == classId })?.providers.filter { connected.contains($0.id) }.count ?? 0
    }

    /// Whether choosing a primary means anything: two **enabled** sources feed the class.
    func offersPrimary(in classId: String) -> Bool {
        prefs.sources(for: classId).enabled.count > 1
    }

    /// Alias kept for call sites that mean “primary UI is available”.
    func canChoosePrimary(in classId: String) -> Bool {
        offersPrimary(in: classId)
    }

    func setEnabled(_ provider: String, in classId: String, _ on: Bool) async {
        var slot = prefs.sources(for: classId)
        if on {
            if !slot.enabled.contains(provider) { slot.enabled.append(provider) }
            if slot.primary == nil { slot.primary = provider }
        } else {
            slot.enabled.removeAll { $0 == provider }
            if slot.primary == provider { slot.primary = slot.enabled.first }
        }
        await apply(slot, to: classId, action: on ? .enable : .disable, provider: provider)
    }

    func setPrimary(_ provider: String, in classId: String) async {
        guard !isPrimary(provider, in: classId) else { return }
        var slot = prefs.sources(for: classId)
        if !slot.enabled.contains(provider) { slot.enabled.append(provider) }
        slot.primary = provider
        await apply(slot, to: classId, action: .setPrimary, provider: provider)
    }

    private func apply(_ slot: V1ClassSources, to classId: String, action: SourcePrefsAction, provider: String) async {
        prefs.classes[classId] = slot
        pendingWrites += 1
        defer { pendingWrites -= 1 }
        do {
            let saved = try await SharpitRetry.run {
                try await client.updateSourcePrefs(action, dataClass: classId, provider: provider, token: try await tokenProvider())
            }
            if pendingWrites == 1 { prefs = saved }
        } catch {
            failures.report("Source non enregistrée. Réessaie plus tard.")
            await load()
        }
    }
}
