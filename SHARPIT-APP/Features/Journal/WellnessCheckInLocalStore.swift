import Foundation

/// Draft + « Plus tard » dismissal for the Résumé « Ressenti du jour » half-sheet.
///
/// Stored in Application Support with
/// `FileProtectionType.completeUntilFirstUserAuthentication` — never UserDefaults.
/// Cleared after a successful save and on sign-out (`LocalAccountData.erase`).
nonisolated struct WellnessCheckInLocalStore: Sendable {
    struct Draft: Codable, Equatable, Sendable {
        var feeling: Int?
        var energy: Int?
        var soreness: Int?
        var stress: Int?
        var notes: String?
        var detailsExpanded: Bool?
    }

    struct Payload: Codable, Equatable, Sendable {
        var athleteId: String
        /// Local training-day ids (`yyyy-MM-dd`) the athlete dismissed with « Plus tard ».
        var dismissedDates: [String]
        var draft: Draft?
        var draftTrainingDayId: String?
    }

    let fileURL: URL

    static let shared = WellnessCheckInLocalStore(
        fileURL: (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appending(path: "WellnessCheckInLocal.json")
    )

    func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    func isDismissed(athleteId: String, localDate: String) -> Bool {
        guard let payload = load(), payload.athleteId == athleteId else { return false }
        return payload.dismissedDates.contains(localDate)
    }

    func dismiss(athleteId: String, localDate: String) {
        var payload = load().flatMap { $0.athleteId == athleteId ? $0 : nil }
            ?? Payload(athleteId: athleteId, dismissedDates: [], draft: nil, draftTrainingDayId: nil)
        if !payload.dismissedDates.contains(localDate) {
            payload.dismissedDates.append(localDate)
        }
        // Drop a draft for another day; keep today's if the athlete comes back.
        if payload.draftTrainingDayId != localDate {
            payload.draft = nil
            payload.draftTrainingDayId = nil
        }
        write(payload)
    }

    func draft(athleteId: String, localDate: String) -> Draft? {
        guard let payload = load(),
              payload.athleteId == athleteId,
              payload.draftTrainingDayId == localDate
        else { return nil }
        return payload.draft
    }

    func saveDraft(_ draft: Draft, athleteId: String, localDate: String) {
        var payload = load().flatMap { $0.athleteId == athleteId ? $0 : nil }
            ?? Payload(athleteId: athleteId, dismissedDates: [], draft: nil, draftTrainingDayId: nil)
        payload.draft = draft
        payload.draftTrainingDayId = localDate
        write(payload)
    }

    /// After a successful save — drop the draft; keep dismissals for other days.
    func clearDraft(athleteId: String) {
        guard var payload = load(), payload.athleteId == athleteId else { return }
        payload.draft = nil
        payload.draftTrainingDayId = nil
        write(payload)
    }

    /// Sign-out / account switch — wipe everything.
    func erase() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ payload: Payload) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(payload)
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            // Local convenience only — a failed write must never block the sheet.
        }
    }
}
