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
                        physicalNotes: DemoPhysicalNoteClient(),
                        saveFirstName: { _ in await demoLatency() }
                    ),
                    consentsOwed: true,
                    firstName: "Zoé",
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

/// Writes four sessions across the coming week, one every second, as the server streams them.
private struct DemoPlanClient: CoachPlanServing {
    func generateWeek(
        days: Int,
        goalId: String?,
        focus: String?,
        startDate: Date?,
        token: String,
        onDraft: @escaping @Sendable ([V1GeneratedSession]) -> Void
    ) async throws -> V1GeneratedPlan {
        let day = { (offset: Int) in TrainingDayId.today(now: Calendar.current.date(byAdding: .day, value: offset, to: .now)!) }
        let sessions = [
            V1GeneratedSession(date: day(1), type: .run, intensity: "ENDURANCE", title: "Footing en endurance", description: "", durationMin: 45, load: 40),
            V1GeneratedSession(
                date: day(3), type: .run, intensity: "THRESHOLD", title: "Seuil 3 × 8 min",
                description: "3 × 8 min au seuil, 2 min de trot entre les blocs.", durationMin: 55, load: 62,
                rationale: "Ta forme le permet : une séance clé cette semaine, sur terrain plat pour ménager le genou.",
                breakdown: V1PlannedSessionBreakdown(steps: [
                    V1PlannedSessionStep(key: "0-0", label: "Échauffement", detail: "15 min", target: "5:20–5:50 /km"),
                    V1PlannedSessionStep(key: "1-0", label: "Bloc", detail: "8 min", target: "4:02–4:10 /km", repeatCount: 3),
                    V1PlannedSessionStep(key: "1-1", label: "Récup", detail: "2 min", target: nil, repeatCount: 3),
                    V1PlannedSessionStep(key: "2-0", label: "Retour au calme", detail: "10 min", target: "5:30–6:00 /km"),
                ])
            ),
            V1GeneratedSession(date: day(4), type: .strength, intensity: "MODERATE", title: "Renforcement tronc et hanches", description: "", durationMin: 30, load: 20),
            V1GeneratedSession(date: day(6), type: .run, intensity: "ENDURANCE", title: "Sortie longue", description: "", durationMin: 80, load: 70),
        ]
        try await Task.sleep(for: .seconds(2))
        for count in 1...sessions.count {
            onDraft(Array(sessions.prefix(count)))
            try await Task.sleep(for: .seconds(1))
        }
        return V1GeneratedPlan(summary: "Une semaine d'installation : du volume facile, une séance de qualité.", sessions: sessions)
    }


    func insertWeek(_ sessions: [V1GeneratedSession], goalId: String?, token: String) async throws {
        await demoLatency()
    }
}

private struct DemoPhysicalNoteClient: PhysicalNoteCreating {
    func createNote(_ input: CreatePhysicalNoteInput, token: String) async throws {}
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
