@preconcurrency import ActivityKit
import Foundation
import UserNotifications

/// ActivityKit's `Activity` is not `Sendable`; the process owns one guided-session activity.
private struct GuidedStrengthRestActivityBox: @unchecked Sendable {
    let activity: Activity<GuidedStrengthRestAttributes>
}

/// Live Activity for the whole guided strength follow — active sets + rest timer + end notif.
@MainActor
final class GuidedStrengthRestLiveActivityController {
    static let shared = GuidedStrengthRestLiveActivityController()

    static let notificationId = "guided-strength-rest-end"

    private var activity: Activity<GuidedStrengthRestAttributes>?
    private var kind: GuidedStrengthRestAttributes.Kind = .active
    private var nextExercise = ""
    private var nextSetLine = ""
    private var restStartedAt: Date?
    private var sessionTitle = ""
    private var startedAt = Date()

    /// Start or refresh the « séance en cours » activity (call while still foreground / on background).
    func ensureActive(
        sessionTitle: String,
        startedAt: Date,
        nextExercise: String,
        nextSetLine: String
    ) {
        // Don't clobber an in-flight rest countdown.
        if activity != nil, kind == .resting { return }

        self.sessionTitle = sessionTitle
        self.startedAt = startedAt
        self.nextExercise = nextExercise
        self.nextSetLine = nextSetLine
        self.kind = .active
        cancelNotification()

        let state = GuidedStrengthRestAttributes.ContentState(
            kind: .active,
            nextExercise: nextExercise,
            nextSetLine: nextSetLine
        )
        upsert(state: state, staleDate: nil)
    }

    func startRest(
        sessionTitle: String,
        startedAt: Date,
        endsAt: Date,
        nextExercise: String,
        nextSetLine: String
    ) {
        self.sessionTitle = sessionTitle
        self.startedAt = startedAt
        self.nextExercise = nextExercise
        self.nextSetLine = nextSetLine
        self.kind = .resting
        self.restStartedAt = .now
        scheduleNotification(endsAt: endsAt, nextExercise: nextExercise, nextSetLine: nextSetLine)

        let state = GuidedStrengthRestAttributes.ContentState(
            kind: .resting,
            endsAt: endsAt,
            isPaused: false,
            nextExercise: nextExercise,
            nextSetLine: nextSetLine,
            restStartedAt: restStartedAt
        )
        upsert(state: state, staleDate: endsAt)
    }

    func updateEndsAt(_ endsAt: Date) {
        kind = .resting
        scheduleNotification(endsAt: endsAt, nextExercise: nextExercise, nextSetLine: nextSetLine)
        guard activity != nil else { return }
        let state = GuidedStrengthRestAttributes.ContentState(
            kind: .resting,
            endsAt: endsAt,
            isPaused: false,
            nextExercise: nextExercise,
            nextSetLine: nextSetLine,
            restStartedAt: restStartedAt
        )
        upsert(state: state, staleDate: endsAt)
    }

    func setPaused(remaining: Int) {
        kind = .resting
        cancelNotification()
        guard activity != nil else { return }
        let state = GuidedStrengthRestAttributes.ContentState(
            kind: .resting,
            endsAt: nil,
            remainingWhenPaused: remaining,
            isPaused: true,
            nextExercise: nextExercise,
            nextSetLine: nextSetLine
        )
        upsert(state: state, staleDate: nil)
    }

    /// After rest: keep the Live Activity, switch back to session elapsed.
    func resumeActive(nextExercise: String, nextSetLine: String) {
        cancelNotification()
        self.nextExercise = nextExercise
        self.nextSetLine = nextSetLine
        self.kind = .active
        guard activity != nil else { return }
        let state = GuidedStrengthRestAttributes.ContentState(
            kind: .active,
            nextExercise: nextExercise,
            nextSetLine: nextSetLine
        )
        upsert(state: state, staleDate: nil)
    }

    func end() {
        cancelNotification()
        guard let activity else { return }
        let box = GuidedStrengthRestActivityBox(activity: activity)
        self.activity = nil
        kind = .active
        nextExercise = ""
        nextSetLine = ""
        Task { await Self.dismiss(box: box) }
    }

    private func upsert(
        state: GuidedStrengthRestAttributes.ContentState,
        staleDate: Date?
    ) {
        let allowed = GuidedStrengthRestLiveActivityGate.shouldStart(
            preferenceEnabled: GuidedStrengthRestLiveActivityPreference.isEnabled,
            activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled
        )
        guard allowed else { return }

        if let activity {
            let box = GuidedStrengthRestActivityBox(activity: activity)
            Task { await Self.push(state, box: box, staleDate: staleDate) }
            return
        }

        do {
            activity = try Activity.request(
                attributes: GuidedStrengthRestAttributes(
                    sessionTitle: sessionTitle,
                    startedAt: startedAt
                ),
                content: .init(state: state, staleDate: staleDate),
                pushType: nil
            )
        } catch {
            // System denied or budget exhausted — rest notification may still fire.
        }
    }

    private func scheduleNotification(endsAt: Date, nextExercise: String, nextSetLine: String) {
        cancelNotification()
        let delay = endsAt.timeIntervalSinceNow
        guard delay > 0.5 else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Repos terminé")
        content.body = GuidedStrengthRestLiveActivityCopy.subtitle(
            nextExercise: nextExercise,
            nextSetLine: nextSetLine
        )
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notificationId,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
    }

    private static func push(
        _ state: GuidedStrengthRestAttributes.ContentState,
        box: GuidedStrengthRestActivityBox,
        staleDate: Date?
    ) async {
        await box.activity.update(.init(state: state, staleDate: staleDate))
    }

    private static func dismiss(box: GuidedStrengthRestActivityBox) async {
        await box.activity.end(nil, dismissalPolicy: .immediate)
    }
}
