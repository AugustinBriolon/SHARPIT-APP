import SwiftUI
import UIKit

/// Re-enables the system interactive pop gesture (swipe from left edge) when
/// `.toolbar(.hidden, for: .navigationBar)` is active.
///
/// By default, UIKit disables `interactivePopGestureRecognizer` when the navigation
/// bar is hidden. This representable hooks into the hosting navigation controller's
/// gesture recognizer and restores swipe-to-dismiss behavior smoothly without breaking
/// navigation stack state.
struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PopGestureController {
        PopGestureController()
    }

    func updateUIViewController(_ uiViewController: PopGestureController, context: Context) {}

    final class PopGestureController: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachGestureRecognizer()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // Leave navigation controller gesture clean if popped
            if isMovingFromParent {
                navigationController?.interactivePopGestureRecognizer?.delegate = nil
            }
        }

        private func attachGestureRecognizer() {
            guard let nav = navigationController else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = true
            nav.interactivePopGestureRecognizer?.delegate = self
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let nav = navigationController else { return false }
            // Only allow edge pop if there's more than 1 view controller on the stack
            return nav.viewControllers.count > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Allows the edge gesture to begin alongside scroll views
            true
        }
    }
}

extension View {
    /// Restores the interactive swipe-from-left edge pop gesture when the navigation bar is hidden.
    func enableInteractivePopGesture() -> some View {
        background(InteractivePopGestureEnabler())
    }
}
