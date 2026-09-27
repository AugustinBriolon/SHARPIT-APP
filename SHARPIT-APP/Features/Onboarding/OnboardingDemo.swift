#if DEBUG
import Foundation
import SwiftUI

/// The first-login wizard on in-memory services, for building and checking it by hand in the
/// simulator without an account or a server. Debug builds only: launched with the
/// `-SharpitOnboardingDemo` argument (`SharpitApp`).
enum OnboardingDemo {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-SharpitOnboardingDemo")
    }
}

struct OnboardingDemoHost: View {
    @State private var finished = false

    var body: some View {
        if finished {
            ContentUnavailableView(
                "Onboarding terminé",
                systemImage: "checkmark.circle",
                description: Text("Relance l'app pour le refaire.")
            )
        } else {
            OnboardingView(
                store: OnboardingStore(
                    services: OnboardingServices(
                        profile: DemoProfileClient(),
                        goals: DemoGoalClient(),
                        onboarding: DemoOnboardingClient(),
                        consents: DemoConsentClient(),
                        plan: DemoPlanClient(),
                        addSession: { _, _ in await demoLatency() }
                    ),
                    consentsOwed: true,
                    tokenProvider: { "demo" }
                ),
                appleHealth: AppleHealthSource(reader: HealthKitReader(), client: SharpitClient()),
                syncClient: DemoSyncClient(),
                tokenProvider: { "demo" }
            ) {
                finished = true
            }
        }
    }
}

/// A beat of network, so busy states show as they do for real.
private func demoLatency() async {
    try? await Task.sleep(for: .milliseconds(600))
}

private struct DemoProfileClient: AthleteProfileServing {
    func athleteProfile(token: String) async throws -> V1AthleteProfile {
        await demoLatency()
        return try JSONDecoder().decode(V1AthleteProfile.self, from: Data("{}".utf8))
    }

    func patchAthleteProfile(_ patch: AthleteProfilePatch, token: String) async throws -> V1AthleteProfile {
        await demoLatency()
        return try JSONDecoder().decode(V1AthleteProfile.self, from: Data("{}".utf8))
    }

    func thresholdHistory(token: String) async throws -> [V1ThresholdSnapshot] { [] }
}

private struct DemoGoalClient: GoalServing {
    func goals(token: String) async throws -> [V1Goal] { [] }

    func createGoal(_ input: CreateGoalInput, token: String) async throws -> V1Goal {
        await demoLatency()
        return V1Goal(title: input.title, kind: input.kind)
    }

    func toggleAchieved(id: String, achieved: Bool, token: String) async throws -> V1Goal {
        V1Goal(id: id, title: "", kind: .race)
    }

    func deleteGoal(id: String, token: String) async throws {}
}

private struct DemoOnboardingClient: OnboardingServing {
    func completeOnboarding(token: String) async throws {
        await demoLatency()
    }
}

private struct DemoConsentClient: PrivacyConsentServing {
    func consents(token: String) async throws -> V1PrivacyConsents {
        V1PrivacyConsents(currentPrivacyVersion: "demo")
    }

    func updateConsents(_ update: PrivacyConsentUpdate, token: String) async throws -> V1PrivacyConsents {
        await demoLatency()
        return V1PrivacyConsents(currentPrivacyVersion: "demo")
    }
}

/// Reasons for a few seconds, then plans four sessions across the coming week.
private struct DemoPlanClient: CoachPlanServing {
    func generateWeek(
        days: Int,
        goalId: String?,
        focus: String?,
        startDate: Date?,
        token: String,
        onReasoning: @escaping @Sendable (String) -> Void
    ) async throws -> V1GeneratedPlan {
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(120))
            onReasoning("…")
        }
        let day = { (offset: Int) in TrainingDayId.today(now: Calendar.current.date(byAdding: .day, value: offset, to: .now)!) }
        return V1GeneratedPlan(summary: "Une semaine d'installation : du volume facile, une séance de qualité.", sessions: [
            V1GeneratedSession(date: day(1), type: .run, intensity: "ENDURANCE", title: "Footing en endurance", description: "", durationMin: 45, load: 40),
            V1GeneratedSession(date: day(3), type: .run, intensity: "THRESHOLD", title: "Seuil 3 × 8 min", description: "", durationMin: 55, load: 62),
            V1GeneratedSession(date: day(4), type: .strength, intensity: "MODERATE", title: "Renforcement tronc et hanches", description: "", durationMin: 30, load: 20),
            V1GeneratedSession(date: day(6), type: .run, intensity: "ENDURANCE", title: "Sortie longue", description: "", durationMin: 80, load: 70),
        ])
    }

    func adaptPlan(days: Int, focus: String?, token: String, onReasoning: @escaping @Sendable (String) -> Void) async throws -> V1AdaptPlanResult {
        V1AdaptPlanResult(summary: "", changes: [])
    }
}

private struct DemoSyncClient: SyncServing {
    func syncStatus(token: String) async throws -> V1SyncStatus {
        V1SyncStatus(lastSyncAt: nil, providers: [])
    }

    func sync(token: String) async throws -> V1SyncStatus {
        V1SyncStatus(lastSyncAt: nil, providers: [])
    }
}
#endif
