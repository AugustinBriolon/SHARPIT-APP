import SwiftUI

/// Paramètres → Langue: the device's language, French or English (iOS ADR 0019).
///
/// The bundle resolves its language once per launch, so a pick applies when SharpIt next opens;
/// the page says so rather than half-switching the screens already loaded. The profile learns
/// the language now, so pushes and the coach follow it from the next one.
struct LanguageSettingsView: View {
    let client: any AthleteProfileServing
    let tokenProvider: () async throws -> String

    @State private var chosen = AppLanguage.chosen

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        select(language)
                    } label: {
                        row(language)
                    }
                    .accessibilityAddTraits(chosen == language ? [.isSelected] : [])
                }
            } footer: {
                SharpitListFooter(footer)
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("Langue")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footer: String {
        chosen == AppLanguage.chosenAtLaunch
            ? String(localized: "Les écrans, les notifications et les réponses du coach suivent cette langue.")
            : String(localized: "Ferme puis rouvre SharpIt pour passer à cette langue.")
    }

    private func row(_ language: AppLanguage) -> some View {
        HStack {
            Text(language.displayName)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
            Spacer(minLength: 0)
            if chosen == language {
                Image(systemName: "checkmark")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }

    private func select(_ language: AppLanguage) {
        guard chosen != language else { return }
        AppLanguage.choose(language)
        chosen = language
        // The device's language is learned at the next launch, once the bundle has resolved it.
        guard language != .system else { return }
        Task {
            guard let token = try? await tokenProvider() else { return }
            var patch = AthleteProfilePatch()
            patch.set(.locale, string: language.rawValue)
            _ = try? await client.patchAthleteProfile(patch, token: token)
        }
    }
}

extension AppLanguage {
    /// Each language under its own name, as iOS lists them; the device's in the app's language.
    var displayName: String {
        switch self {
        case .system: String(localized: "Langue de l'appareil")
        case .french: "Français"
        case .english: "English"
        }
    }

    /// The pick as this launch read it, before any change on the page.
    static let chosenAtLaunch = AppLanguage.chosen

    /// Launch side: tells the profile which language the app shows, when it does not know yet.
    static func syncToProfile(client: any AthleteProfileServing, tokenProvider: () async throws -> String) async {
        publishToExtensions()
        guard let token = try? await tokenProvider(),
              let profile = try? await client.athleteProfile(token: token),
              profile.locale != current.rawValue else { return }
        var patch = AthleteProfilePatch()
        patch.set(.locale, string: current.rawValue)
        _ = try? await client.patchAthleteProfile(patch, token: token)
    }
}
