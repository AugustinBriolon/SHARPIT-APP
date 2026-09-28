import Foundation
import Observation

/// « Ajuster le planning »: the coach reads what was done and proposes changes to the sessions of
/// the next two weeks; the athlete keeps some and applies them. The server has already taken out
/// what its safety check rejects, so every change shown can be applied.
@Observable
@MainActor
final class PlanAdjustmentStore {
    enum Phase: Equatable {
        case idle
        case analyzing
        case ready(V1AdaptPlanResult, selected: Set<Int>)
        case applying(V1AdaptPlanResult, selected: Set<Int>)
        case failed(String)
    }

    /// How far ahead the coach adjusts.
    static let horizonDays = 14

    private(set) var phase: Phase = .idle
    /// What changed for the athlete — fatigue, a pain, a trip. Optional.
    var focus = ""
    /// Why the last apply failed, shown with the changes still on screen.
    private(set) var applyError: String?

    private let client: any PlanAdjustmentServing
    private let tokenProvider: () async throws -> String

    init(
        client: any PlanAdjustmentServing = CoachPlanClient(),
        tokenProvider: @escaping () async throws -> String
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    var isAnalyzing: Bool { phase == .analyzing }

    func start() async {
        phase = .analyzing
        applyError = nil
        do {
            let result = try await client.adaptPlan(
                days: Self.horizonDays,
                focus: focus.trimmingCharacters(in: .whitespacesAndNewlines),
                token: try await tokenProvider(),
                onReasoning: { _ in }
            )
            phase = .ready(result, selected: Set(result.changes.indices))
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func toggle(_ index: Int) {
        guard case .ready(let result, var selected) = phase else { return }
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
        phase = .ready(result, selected: selected)
    }

    func reset() {
        phase = .idle
        applyError = nil
    }

    /// Applies the changes kept; returns how many, or nil when it failed and the changes stay.
    func apply() async -> Int? {
        guard case .ready(let result, let selected) = phase, !selected.isEmpty else { return nil }
        let kept = selected.sorted().map { result.changes[$0] }
        phase = .applying(result, selected: selected)
        applyError = nil
        do {
            try await client.applyAdjustments(kept, token: try await tokenProvider())
            phase = .idle
            return kept.count
        } catch {
            applyError = Self.message(for: error)
            phase = .ready(result, selected: selected)
            return nil
        }
    }

    private static func message(for error: Error) -> String {
        if case CoachPlanError.custom(let message) = error { return message }
        return SharpitErrorGuidance.message(for: error, subject: "L'ajustement")
    }
}
