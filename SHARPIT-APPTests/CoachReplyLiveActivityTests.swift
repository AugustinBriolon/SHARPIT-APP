import Foundation
import Testing
@testable import Sharpit

@Test func previewKeepsAShortLineAndCapsLongOnes() {
    #expect(CoachReplyPreview.line(from: "  Oui.  ") == "Oui.")
    let long = String(repeating: "a", count: 120)
    let line = CoachReplyPreview.line(from: long)
    #expect(line.count <= 80)
    #expect(line.hasSuffix("…"))
}

@Test func headlineAndDetailMatchPhase() {
    #expect(CoachReplyLiveActivityCopy.headline(phase: .replying) == "Te répond…")
    #expect(CoachReplyLiveActivityCopy.headline(phase: .ready) == "Réponse prête")
    #expect(CoachReplyLiveActivityCopy.headline(phase: .failed) == "Réponse interrompue")
    #expect(CoachReplyLiveActivityCopy.detail(phase: .replying, preview: "TSB +4") == nil)
    #expect(CoachReplyLiveActivityCopy.detail(phase: .ready, preview: "") == nil)
    #expect(CoachReplyLiveActivityCopy.detail(phase: .ready, preview: "TSB +4") == "TSB +4")
    #expect(CoachReplyLiveActivityCopy.detail(phase: .failed, preview: "") == "Rouvre SharpIt pour la reprendre.")
}

@Test func startsOnlyWhenReplyingAndEnabled() {
    #expect(CoachReplyLiveActivityGate.shouldStart(
        isReplying: true, preferenceEnabled: true, activitiesEnabled: true
    ))
    #expect(!CoachReplyLiveActivityGate.shouldStart(
        isReplying: false, preferenceEnabled: true, activitiesEnabled: true
    ))
    #expect(!CoachReplyLiveActivityGate.shouldStart(
        isReplying: true, preferenceEnabled: false, activitiesEnabled: true
    ))
    #expect(!CoachReplyLiveActivityGate.shouldStart(
        isReplying: true, preferenceEnabled: true, activitiesEnabled: false
    ))
}

@Test func liveActivityPreferenceDefaultsToOn() {
    let suite = UserDefaults(suiteName: "group.app.sharpit.ios")
    suite?.removeObject(forKey: CoachReplyLiveActivityPreference.key)
    #expect(CoachReplyLiveActivityPreference.isEnabled)

    CoachReplyLiveActivityPreference.setEnabled(false)
    #expect(!CoachReplyLiveActivityPreference.isEnabled)

    CoachReplyLiveActivityPreference.setEnabled(true)
    #expect(CoachReplyLiveActivityPreference.isEnabled)
    suite?.removeObject(forKey: CoachReplyLiveActivityPreference.key)
}
