import SwiftUI
import WidgetKit

@main
struct SharpItWidgetsBundle: WidgetBundle {
    init() {
        AppLanguage.adoptAppLanguage()
    }

    var body: some Widget {
        TodaySessionWidget()
        LastActivityWidget()
        VerdictWidget()
        NutritionWidget()
        SleepWidget()
        EnergyBankWidget() // ADR-079. Callers: WidgetKit. User: Bevel gaps plan.
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
