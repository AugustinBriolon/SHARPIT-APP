import Foundation
import Testing
import UIKit
import SwiftUI
@testable import Sharpit

@Suite struct ActivityInteractiveMapTests {
    @Test func interactiveRouteMapViewInitializesWithCoordinates() {
        let route = [
            V1ActivityCoordinate(latitude: 45.764, longitude: 4.8357),
            V1ActivityCoordinate(latitude: 45.765, longitude: 4.8360),
            V1ActivityCoordinate(latitude: 45.766, longitude: 4.8370)
        ]

        let view = InteractiveRouteMapView(
            route: route,
            tone: .green,
            title: "Course matinale",
            sportLabel: "Course à pied",
            sportSymbol: "figure.run",
            distanceM: 5200,
            elevationM: 85,
            duration: 1650
        )

        #expect(view.route.count == 3)
        #expect(view.title == "Course matinale")
        #expect(view.distanceM == 5200)
        #expect(view.elevationM == 85)
        #expect(view.duration == 1650)
    }

    @Test func mapStyleOptionsProvideCorrectLabelsAndCases() {
        let options = InteractiveRouteMapView.MapStyleOption.allCases
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
