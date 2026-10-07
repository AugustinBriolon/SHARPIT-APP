@preconcurrency import ActivityKit
import Foundation

/// ActivityKit's `Activity` is not `Sendable`; the process owns one coach-reply activity.
private struct CoachReplyActivityBox: @unchecked Sendable {
    let activity: Activity<CoachReplyAttributes>
}

/// Starts and updates the coach-reply Live Activity from the app process.
@MainActor
final class CoachReplyLiveActivityController {
    static let shared = CoachReplyLiveActivityController()

    private var activity: Activity<CoachReplyAttributes>?
    private var endTask: Task<Void, Never>?
    /// How long « Réponse prête » / failure stays before the activity ends.
    private let dwell: Duration

    init(dwell: Duration = .seconds(4)) {
        self.dwell = dwell
    }

    /// Call when the scene backgrounds during a reply.
    func startIfNeeded(conversationId: String, isReplying: Bool) {
        let allowed = CoachReplyLiveActivityGate.shouldStart(
            isReplying: isReplying,
            preferenceEnabled: CoachReplyLiveActivityPreference.isEnabled,
            activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled
        )
        guard allowed else { return }
        guard activity == nil else { return }

        let attributes = CoachReplyAttributes(conversationId: conversationId)
        let state = CoachReplyAttributes.ContentState(phase: .replying)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // System denied or budget exhausted — stay quiet.
        }
    }

    func markReady(preview: String) {
        guard let activity else { return }
        let state = CoachReplyAttributes.ContentState(phase: .ready, preview: preview)
        let box = CoachReplyActivityBox(activity: activity)
        Task { await Self.push(state, box: box) }
        scheduleEnd()
    }

    func markFailed() {
        guard let activity else { return }
        let state = CoachReplyAttributes.ContentState(phase: .failed)
        let box = CoachReplyActivityBox(activity: activity)
        Task { await Self.push(state, box: box) }
        scheduleEnd()
    }

    func end() {
        endTask?.cancel()
        endTask = nil
        guard let activity else { return }
        let box = CoachReplyActivityBox(activity: activity)
        self.activity = nil
        Task { await Self.dismiss(box: box) }
    }

    private func scheduleEnd() {
        endTask?.cancel()
        endTask = Task { @MainActor in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            end()
        }
    }

    private static func push(
        _ state: CoachReplyAttributes.ContentState,
        box: CoachReplyActivityBox
    ) async {
        await box.activity.update(.init(state: state, staleDate: nil))
    }

    private static func dismiss(box: CoachReplyActivityBox) async {
        await box.activity.end(nil, dismissalPolicy: .immediate)
    }
}
