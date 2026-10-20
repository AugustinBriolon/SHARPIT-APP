import Foundation

/// What the athlete answered before having an account (SHARPIT ADR-097): the profile steps,
/// identity to injuries. Once an account exists the wizard replays it through the writes each
/// step would have made, then deletes it.
nonisolated struct OnboardingDraft: Codable, Equatable, Sendable {
    /// The step reached, so a relaunch before sign-up reopens it.
    var step: OnboardingStep = .identity
    /// The steps left whose write the account will replay, in the path's order.
    var answered: Set<OnboardingStep> = []
    var identity = OnboardingIdentityDraft()
    var motivations: Set<SharpitFeature> = []
    var sports: [String] = []
    var ownedEquipment: Set<String> = []
    var strengthVenue: V1AthleteEquipment.StrengthVenue = .bodyweight
    var availability = V1TrainingAvailability()
    var intention = OnboardingIntentionDraft()
    var injuries: [OnboardingInjuryDraft] = []
}

/// The draft on disk: Application Support, protected until first unlock and out of device
/// backups (`docs/adr/0017`) — the injuries are health data. One per iPhone: there is no account
/// to key it by yet.
nonisolated struct OnboardingDraftFile: Sendable {
    let fileURL: URL

    static let shared = OnboardingDraftFile(
        fileURL: (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appending(path: "OnboardingDraft.json")
    )

    func load() -> OnboardingDraft? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(OnboardingDraft.self, from: data)
    }

    func save(_ draft: OnboardingDraft) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(draft).write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            // An atomic write replaces the file and drops the flag.
            BackupExclusion.exclude(fileURL)
        } catch {
            // A convenience: a failed write only means a relaunch starts the wizard over.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
