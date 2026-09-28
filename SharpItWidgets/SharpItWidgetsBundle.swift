import SwiftUI
import WidgetKit

@main
struct SharpItWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodaySessionWidget()
        VerdictWidget()
    }
}
