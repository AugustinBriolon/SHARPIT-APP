import SwiftUI

/// Réglages → Profil: the athlete's stable attributes and the rhythm they aim for.
///
/// Identity only. The living body signals — weight, composition — are Corps, and the
/// yardstick load is read against is Seuils & repères.
struct ProfileView: View {
    @State private var store: AthleteProfileStore
    @State private var form = ProfileFormState()

    init(client: any AthleteProfileServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: AthleteProfileStore(client: client, tokenProvider: tokenProvider))
    }

    private static let ownedFields: [ProfileFormField] = [
        .heightCm, .targetWeightKg, .sleepTargetHours, .sleepBedtime,
    ]

    var body: some View {
        ProfileFormScaffold(
            title: "Profil",
            subtitle: "Ta taille, ton âge et le rythme que tu visées — ce que le coach lit avant de conseiller.",
            store: store,
            form: $form,
            ownedFields: Self.ownedFields
        ) {
            SharpitFieldGroup("Toi") {
                SharpitField(
                    label: "Taille",
                    text: $form.heightCm,
                    placeholder: "178",
                    unit: "cm",
                    error: form.error(for: .heightCm)
                )
                birthDateField
            }
            SharpitFieldGroup(
                "Rythme visé",
                note: "Le sommeil visé sert de repère à la lecture de tes nuits — il ne déclenche aucune alerte."
            ) {
                SharpitField(
                    label: "Objectif sommeil",
                    text: $form.sleepTargetHours,
                    placeholder: "8",
                    unit: "h",
                    keyboard: .decimalPad,
                    hint: "Entre 4 et 12 heures.",
                    error: form.error(for: .sleepTargetHours)
                )
                SharpitField(
                    label: "Coucher visé",
                    text: $form.sleepBedtime,
                    placeholder: "22:30",
                    keyboard: .numbersAndPunctuation,
                    error: form.error(for: .sleepBedtime)
                )
                SharpitField(
                    label: "Objectif de poids",
                    text: $form.targetWeightKg,
                    placeholder: "72",
                    unit: "kg",
                    keyboard: .decimalPad,
                    hint: "Optionnel. Le coach en tient compte dans la lecture nutrition.",
                    error: form.error(for: .targetWeightKg)
                )
            }
        }
    }

    /// A date, not a typed field: a picker cannot hold a day that does not exist, and the
    /// server reads a birth date as a calendar day rather than an instant.
    private var birthDateField: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            DatePicker(
                "Date de naissance",
                selection: Binding(
                    get: { form.birthDate ?? Self.defaultBirthDate },
                    set: { form.birthDate = $0 }
                ),
                in: Self.birthDateRange,
                displayedComponents: .date
            )
            .font(SharpitTypography.body)
            if let age = ProfileAge.years(since: form.birthDate) {
                Text("\(age) ans")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    /// The web refuses a birth year before 1920 or a date in the future.
    private static let birthDateRange: ClosedRange<Date> = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let earliest = utc.date(from: DateComponents(year: 1920, month: 1, day: 1))!
        return earliest...Date.now
    }()

    /// Where the picker opens for an athlete who never set one — a plausible year, so the
    /// first scroll is short.
    private static let defaultBirthDate: Date = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
    }()
}

/// The athlete's age in whole years, as the web's `athleteAgeYears` computes it.
nonisolated enum ProfileAge {
    static func years(since birthDate: Date?, now: Date = .now) -> Int? {
        guard let birthDate else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let years = utc.dateComponents([.year], from: birthDate, to: now).year, years >= 0 else {
            return nil
        }
        return years
    }
}
