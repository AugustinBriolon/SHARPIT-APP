import ClerkKit
import ClerkKitUI
import SwiftData
import SwiftUI

@main
struct SharpitApp: App {
    @UIApplicationDelegateAdaptor(SharpitAppDelegate.self) private var appDelegate
    /// Nil only when both on-disk and in-memory containers failed — the app then shows a
    /// cannot-start screen instead of crashing via `try!`.
    private let modelContainer: ModelContainer?
    @State private var linkInbox = IncomingLinkInbox()

    init() {
        // First, so a crash anywhere in launch is reported.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            CrashReporting.start()
            Task { await AppDistribution.prepare() }
        }
        SharpitFonts.register()
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)
        modelContainer = Self.makeModelContainer()
    }

    private static func makeModelContainer() -> ModelContainer? {
        do {
            return try SharpitPersistence.makeContainer()
        } catch {
            // Disk failure: fall back to an in-memory store so the athlete can still open the app.
            do {
                return try SharpitPersistence.makeContainer(inMemory: true)
            } catch {
                return nil
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                launchedApp
                    .modelContainer(modelContainer)
            } else {
                PersistenceCannotStartView()
            }
        }
    }

    @ViewBuilder
    private var launchedApp: some View {
        #if DEBUG
        if OnboardingDemo.isRequested {
            OnboardingDemoHost()
                .sharpitAppearance()
        } else if WeeklyReviewDemo.isRequested {
            WeeklyReviewDemoHost()
                .sharpitAppearance()
        } else if CoachDemo.isRequested {
            CoachDemoHost()
                .sharpitAppearance()
        } else {
            app
        }
        #else
        app
        #endif
    }

    private var app: some View {
        AuthGate {
            // The legal wall, then the web's onboarding, before a new account sees the tabs.
            AccountGate {
                RootView()
            }
        }
        .environment(Clerk.shared)
        .environment(linkInbox)
        .environment(\.clerkTheme, .sharpit)
        // Per iPhone, never synced (Paramètres → Apparence).
        .sharpitAppearance()
        .onOpenURL { url in
            linkInbox.receive(url)
            Task {
                try? await Clerk.shared.handle(url)
            }
        }
    }
}

/// Shown when SwiftData cannot open any store — prefer a clear stop over a launch crash.
private struct PersistenceCannotStartView: View {
    var body: some View {
        VStack(spacing: SharpitSpacing.md) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(SharpitColor.signalRisk)
            Text("SharpIt ne peut pas démarrer")
                .font(SharpitTypography.pageTitle)
                .foregroundStyle(SharpitColor.foreground)
            Text("Le stockage local est indisponible. Relance l’app, ou libère de l’espace sur cet iPhone.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(SharpitSpacing.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharpitCanvasBackground())
        .sharpitAppearance()
    }
}
