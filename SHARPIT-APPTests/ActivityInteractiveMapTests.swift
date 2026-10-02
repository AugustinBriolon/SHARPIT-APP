import Foundation
import Testing
import UIKit
import SwiftUI
@testable import Sharpit

@Suite struct ActivityInteractiveMapTests {
    @Test func mapStyleOptionsProvideCorrectLabelsAndCases() {
        let options = MapStyleOption.allCases
        #expect(options.count == 3)
        #expect(options.map(\.rawValue) == ["Plan", "Satellite", "Mixte"])
    }

    @Test func interactivePopGestureControllerRequiresMultipleControllers() {
        let controller = InteractivePopGestureEnabler.PopGestureController()
        let panGesture = UIPanGestureRecognizer()

        // Without navigation controller, gesture should not begin
        #expect(controller.gestureRecognizerShouldBegin(panGesture) == false)

        let rootVC = UIViewController()
        let navController = UINavigationController(rootViewController: rootVC)

        // When embedded in root view controller (stack count == 1), should NOT begin to prevent pop freeze
        rootVC.addChild(controller)
        #expect(controller.gestureRecognizerShouldBegin(panGesture) == false)

        // When embedded in a pushed view controller (stack count == 2), should begin
        controller.removeFromParent()
        let pushedVC = UIViewController()
        pushedVC.addChild(controller)
        navController.pushViewController(pushedVC, animated: false)
        #expect(controller.gestureRecognizerShouldBegin(panGesture) == true)
    }

    @Test func simultaneousGestureRecognitionAllowed() {
        let controller = InteractivePopGestureEnabler.PopGestureController()
        let gesture1 = UIPanGestureRecognizer()
        let gesture2 = UIPanGestureRecognizer()

        #expect(controller.gestureRecognizer(gesture1, shouldRecognizeSimultaneouslyWith: gesture2) == true)
    }

    @Test func collapsedActivityBottomBarSubtitleFormatsCorrectly() throws {
        let json = """
        {
            "id": "act-123",
            "type": "RUN",
            "date": "2026-09-22T08:00:00Z",
            "title": "Sortie longue",
            "duration": 3600,
            "runMetrics": {
                "distanceM": 12500,
                "elevationM": 150
            }
        }
        """
        let detail = try JSONDecoder().decode(V1ActivityDetail.self, from: Data(json.utf8))

        let bar = CollapsedActivityBottomBar(
            detail: detail,
            tone: .green,
            onExpand: {}
        )

        #expect(bar.subtitleText.contains("Course"))
        #expect(bar.subtitleText.contains("12.5 km"))
        #expect(bar.subtitleText.contains("150 m D+"))
        #expect(bar.subtitleText.contains("1 h 0 min"))
    }

    @Test func compliancePendingTileInitializesCleanly() {
        let tile = CompliancePendingTile()
        #expect(tile != nil)
    }
}
