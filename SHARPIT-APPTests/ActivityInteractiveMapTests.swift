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

    @Test func theMapCardSaysOnlyTheFiguresTheSessionCarries() {
        let whole = ActivityMapReadout.figures(distanceM: 12_500, duration: 3_600, elevationM: 150)
        #expect(whole.hasPrefix("12,5 km"))
        #expect(whole.contains("1 h 0 min"))
        #expect(whole.contains("150 m"))
        #expect(whole.components(separatedBy: " · ").count == 3)
        #expect(ActivityMapReadout.figures(distanceM: 800, duration: nil, elevationM: 0) == "800 m")
        #expect(ActivityMapReadout.figures(distanceM: nil, duration: nil, elevationM: nil).isEmpty)
    }

    @Test func theMapCardNamesSpeedAsPaceForARun() {
        #expect(ActivityMapReadout.label(.speed, usesPace: true) == "Allure")
        #expect(ActivityMapReadout.label(.speed, usesPace: false) == "Vitesse")
        #expect(ActivityMapReadout.label(.plain, usesPace: true) == "Uni")
    }

    @Test func compliancePendingTileInitializesCleanly() {
        let tile = CompliancePendingTile()
        #expect(tile != nil)
    }
}
