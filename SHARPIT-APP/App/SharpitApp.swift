import ClerkKit
import ClerkKitUI
import SwiftData
import SwiftUI

@main
struct SharpitApp: App {
    @UIApplicationDelegateAdaptor(SharpitAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer

    init() {
        // First, so a crash anywhere in launch is reported.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            CrashReporting.start()
        }
        SharpitFonts.register()
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)
        do {
            modelContainer = try SharpitPersistence.makeContainer()
        } catch {
            // Last-resort in-memory store so a disk failure still launches.
            modelContainer = try! SharpitPersistence.makeContainer(inMemory: true)
        }
    }

    var body: some Scene {
        WindowGroup {
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
        .modelContainer(modelContainer)
    }

    private var app: some View {
        AuthGate {
            // The legal wall, then the web's onboarding, before a new account sees the tabs.
            AccountGate {
                RootView()
            }
        }
        .environment(Clerk.shared)
        .environment(\.clerkTheme, .sharpit)
        // Per iPhone, never synced (Paramètres → Apparence).
        .sharpitAppearance()
        .onOpenURL { url in
            Task {
                try? await Clerk.shared.handle(url)
            }
        }
    }
}
