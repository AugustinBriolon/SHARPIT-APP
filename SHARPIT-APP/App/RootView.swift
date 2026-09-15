import ClerkKit
import ClerkKitUI
import SwiftUI

struct RootView: View {
    @Environment(Clerk.self) private var clerk

    var body: some View {
        TabView {
            Tab("Résumé", systemImage: "sun.max") {
                TodayView(client: SharpitClient(), tokenProvider: liveToken)
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
                NavigationStack {
                    List {
                        Section {
                            HStack {
                                Text("Compte")
                                Spacer()
                                UserButton()
                            }
                        }
                    }
                    .navigationTitle("Moi")
                    .modifier(LiquidNavChrome())
                }
            }
        }
        .modifier(LiquidTabBarModifier())
    }

    @MainActor
    private func liveToken() async throws -> String {
        guard let token = try await clerk.auth.getToken() else {
            throw SharpitAPIError.unauthorized
        }
        return token
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
