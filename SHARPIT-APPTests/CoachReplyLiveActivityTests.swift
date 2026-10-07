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

@Test func subtitleMatchesPhase() {
    #expect(CoachReplyLiveActivityCopy.subtitle(phase: .replying, preview: "") == "Répond…")
    #expect(CoachReplyLiveActivityCopy.subtitle(phase: .ready, preview: "") == "Réponse prête")
    #expect(CoachReplyLiveActivityCopy.subtitle(phase: .ready, preview: "TSB +4") == "Réponse prête · TSB +4")
    #expect(
        CoachReplyLiveActivityCopy.subtitle(phase: .failed, preview: "")
            == "Réponse interrompue · rouvre SharpIt"
    )
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
