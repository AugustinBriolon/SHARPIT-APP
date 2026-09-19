import ClerkKit
import ClerkKitUI
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("Résumé", systemImage: "sun.max") {
                TodayView(
                    client: SharpitClient(),
                    tokenProvider: liveToken,
                    modelContext: modelContext
                )
            }
            Tab(ShellDestination.plan.title, systemImage: ShellDestination.plan.systemImage) {
                PlanView(
                    client: PlannedSessionClient(),
                    tokenProvider: liveToken
                )
            }
            Tab(ShellDestination.coach.title, systemImage: ShellDestination.coach.systemImage) {
                InstrumentShellView(destination: .coach)
            }
            Tab(ShellDestination.activity.title, systemImage: ShellDestination.activity.systemImage) {
                ActivityView(
                    client: ActivityClient(),
                    tokenProvider: liveToken
                )
            }
            Tab(ShellDestination.me.title, systemImage: ShellDestination.me.systemImage) {
                InstrumentShellView(destination: .me) {
                    accountMark
                }
            }
        }
        .background(SharpitCanvasBackground())
        .tint(SharpitColor.primary)
        .modifier(LiquidTabBarModifier())
    }

    private var accountMark: some View {
        HStack(spacing: SharpitSpacing.xs) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(SharpitColor.mutedForeground)
            Spacer(minLength: 0)
            UserButton()
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Compte")
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
                .toolbarBackground(.thinMaterial, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
}
