import SwiftUI

struct RootView: View {
    var body: some View {
        tabView
            .modifier(LiquidTabBarModifier())
    }

    private var tabView: some View {
        TabView {
            Tab("Résumé", systemImage: "sun.max") {
                TodayView()
            }
            Tab("Plan", systemImage: "calendar") {
                PlaceholderTab(title: "Plan")
            }
            Tab("Coach", systemImage: "bubble.left.and.bubble.right") {
                PlaceholderTab(title: "Coach")
            }
            Tab("Activité", systemImage: "figure.run") {
                PlaceholderTab(title: "Activité")
            }
            Tab("Moi", systemImage: "person.crop.circle") {
                PlaceholderTab(title: "Moi")
            }
        }
    }
}

private struct LiquidTabBarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
}
