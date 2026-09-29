import SwiftUI
import WidgetKit

@main
struct SharpItWidgetsBundle: WidgetBundle {
    /// The brand faces live in this extension's bundle too; the widgets speak the app's type.
    init() {
        SharpitFonts.register()
    }

    var body: some Widget {
        TodaySessionWidget()
        VerdictWidget()
        NutritionWidget()
        SleepWidget()
        WeightWidget()
        VolumeWidget()
        RegularityWidget()
        NextGoalWidget()
        CoachWidget()
        CoachControl()
    }
}
