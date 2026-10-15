import Foundation
import Testing
@testable import Sharpit

@Test func guidedRestSubtitleJoinsExerciseAndSet() {
    #expect(
        GuidedStrengthRestLiveActivityCopy.subtitle(
            nextExercise: "Bench Press",
            nextSetLine: "série 2 · 10 × 95 kg"
        ) == "Bench Press · série 2 · 10 × 95 kg"
    )
    #expect(
        GuidedStrengthRestLiveActivityCopy.subtitle(nextExercise: "Squat", nextSetLine: "") == "Squat"
    )
    #expect(
        GuidedStrengthRestLiveActivityCopy.subtitle(nextExercise: "", nextSetLine: "")
            == "Séance en cours"
    )
    #expect(GuidedStrengthRestLiveActivityCopy.eyebrow(kind: .active) == "Séance")
    #expect(GuidedStrengthRestLiveActivityCopy.eyebrow(kind: .resting) == "Repos")
}

@Test func guidedRestPausedLabelFormatsClock() {
    #expect(GuidedStrengthRestLiveActivityCopy.pausedLabel(seconds: 65) == "1:05")
    #expect(GuidedStrengthRestLiveActivityCopy.pausedLabel(seconds: 9) == "0:09")
}

@Test func guidedRestStartsOnlyWhenEnabled() {
    #expect(GuidedStrengthRestLiveActivityGate.shouldStart(
        preferenceEnabled: true, activitiesEnabled: true
    ))
    #expect(!GuidedStrengthRestLiveActivityGate.shouldStart(
        preferenceEnabled: false, activitiesEnabled: true
    ))
    #expect(!GuidedStrengthRestLiveActivityGate.shouldStart(
        preferenceEnabled: true, activitiesEnabled: false
    ))
}

@Test func guidedRestLiveActivityPreferenceDefaultsToOn() {
    let suite = UserDefaults(suiteName: "group.app.sharpit.ios")
    suite?.removeObject(forKey: GuidedStrengthRestLiveActivityPreference.key)
    #expect(GuidedStrengthRestLiveActivityPreference.isEnabled)

    GuidedStrengthRestLiveActivityPreference.setEnabled(false)
    #expect(!GuidedStrengthRestLiveActivityPreference.isEnabled)

    GuidedStrengthRestLiveActivityPreference.setEnabled(true)
    #expect(GuidedStrengthRestLiveActivityPreference.isEnabled)
    suite?.removeObject(forKey: GuidedStrengthRestLiveActivityPreference.key)
}
