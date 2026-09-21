import ClerkKit
import ClerkKitUI
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.modelContext) private var modelContext

    /// Owned here so a surface can send the athlete to another tab — the regularity strip
    /// opening Plan, any "Discuter avec le coach" button opening Coach with its subject.
    @State private var router = ShellRouter()

    /// One client for reading the plan and for linking, so both share a session.
    private let plannedSessionClient = PlannedSessionClient()
    private let activityStatusClient = ActivityStatusClient()
    private let journalClient = JournalClient()
    private let wellnessClient = WellnessClient()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Résumé", systemImage: "sun.max", value: ShellTab.today) {
                TodayView(
                    client: SharpitClient(),
                    tokenProvider: liveToken,
                    modelContext: modelContext,
                    activityStatusClient: activityStatusClient,
                    journalClient: journalClient,
                    wellnessClient: wellnessClient,
                    signalClient: SharpitClient(),
                    syncClient: SharpitClient()
                )
            }
            Tab(
                ShellDestination.plan.title,
                systemImage: ShellDestination.plan.systemImage,
                value: ShellTab.plan
            ) {
                PlanView(
                    client: plannedSessionClient,
                    linker: plannedSessionClient,
                    activityClient: ActivityClient(),
                    tokenProvider: liveToken
                )
            }
            Tab(
                ShellDestination.coach.title,
                systemImage: ShellDestination.coach.systemImage,
                value: ShellTab.coach
            ) {
                CoachView(
                    client: CoachChatClient(),
                    conversations: CoachConversationClient(),
                    tokenProvider: liveToken
                )
            }
            Tab(
                ShellDestination.activity.title,
                systemImage: ShellDestination.activity.systemImage,
                value: ShellTab.activity
            ) {
                ActivityView(
                    client: ActivityClient(),
                    tokenProvider: liveToken
                )
            }
            Tab(
                ShellDestination.me.title,
                systemImage: ShellDestination.me.systemImage,
                value: ShellTab.me
            ) {
                InstrumentShellView(destination: .me) {
                    accountMark
                }
            }
        }
        .background(SharpitCanvasBackground())
        .tint(SharpitColor.primary)
        .environment(router)
        // Every string in this app is French, and so is the web's. Left to the device
        // locale the date strips rendered "M T W T F S S" under French copy.
        .environment(\.locale, Locale(identifier: "fr_FR"))
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
