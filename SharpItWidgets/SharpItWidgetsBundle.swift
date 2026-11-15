import SwiftUI
import WidgetKit

@main
struct SharpItWidgetsBundle: WidgetBundle {
    init() {
        AppLanguage.adoptAppLanguage()
    }

    var body: some Widget {
        ResumeRingsWidget()
        TodaySessionWidget()
        NutritionWidget()
        SleepWidget()
        RecoveryWidget()
        WeightWidget()
        VolumeWidget()
        RegularityWidget()
        NextGoalWidget()
        CoachWidget()
        CoachControl()
        ScanFoodWidget()
        ScanFoodControl()
        CoachReplyLiveActivity()
        GuidedStrengthRestLiveActivity()
    }
}
