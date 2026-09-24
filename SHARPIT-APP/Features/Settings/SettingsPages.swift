import CloudKit
import ClerkKit
import SwiftData
import SwiftUI
import UIKit

// MARK: - Synchronisation iCloud

/// Whether the iCloud copy of the cache works, and when it last moved (`docs/adr/0007`).
struct ICloudSyncView: View {
    let monitor: CloudSyncMonitor

    var body: some View {
        List {
            Section(eyebrow: "Compte iCloud") {
                LabeledContent {
                    Text(ConnectionsReadout.iCloud(monitor.accountStatus))
                        .foregroundStyle(monitor.accountStatus == .available ? SharpitColor.signalRecovery : SharpitColor.mutedForeground)
                } label: {
                    Label {
                        Text("Statut")
                    } icon: {
                        SharpitRowIcon(symbol: "icloud")
                    }
                }
            }
            .sharpitListRows()

            Section(
                eyebrow: "Activité",
                footer: "iCloud garde une copie de ce que l'app a déjà lu, pour l'afficher hors ligne et sur tes autres appareils. Jamais tes réponses de journal ni tes réglages, qui restent sur le serveur."
            ) {
                ForEach([CloudSyncMonitor.Kind.exporting, .importing, .setup], id: \.self) { kind in
                    LabeledContent(kind.label) {
                        Text(eventLabel(monitor.events[kind]))
                            .foregroundStyle(monitor.events[kind]?.succeeded == false ? SharpitColor.signalCaution : SharpitColor.mutedForeground)
                    }
                }
                if let error = monitor.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalCaution)
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .navigationTitle("Synchronisation iCloud")
        .navigationBarTitleDisplayMode(.inline)
        .task { await monitor.refreshAccountStatus() }
        .refreshable { await monitor.refreshAccountStatus() }
    }

    private func eventLabel(_ event: CloudSyncMonitor.Event?) -> String {
        guard let event else { return "Jamais" }
        let when = Date.RelativeFormatStyle(presentation: .named, locale: SharpitLocale.french)
            .format(event.endedAt)
        return event.succeeded ? when.capitalizedFirst : "Échec · \(when)"
    }
}

// MARK: - Compte

/// Who the athlete is, edited where it is read.
///
/// First and last name are Clerk's and saved to Clerk as they are typed; sex, height and birth
/// date are the profile's and saved through `AthleteProfilePatch`. The e-mail, the password and
/// the photo live in Clerk's own account sheet — the one row that opens it.
struct AccountView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var store: AthleteProfileStore
    @State private var form = ProfileFormState()
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var hasLoaded = false
    @State private var nameSave: Task<Void, Never>?
    @State private var profileSave: Task<Void, Never>?
    @State private var isEditingAccount = false

    init(
        profileClient: any AthleteProfileServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext?
    ) {
        _store = State(initialValue: AthleteProfileStore(
            client: profileClient,
            tokenProvider: tokenProvider,
            modelContext: modelContext
        ))
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: SharpitSpacing.sm) {
                    AccountAvatar(size: 88)
                    Button("Photo, e-mail et mot de passe") { isEditingAccount = true }
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(SharpitColor.primary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section(eyebrow: "Identité") {
                LabeledContent("Prénom") {
                    TextField("Prénom", text: $firstName)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                }
                LabeledContent("Nom") {
                    TextField("Nom", text: $lastName)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.familyName)
                        .submitLabel(.done)
                }
            }
            .sharpitListRows()

            Section(
                eyebrow: "Profil",
                footer: "Le sexe, la taille et l'âge servent à l'âge biologique et aux normes de fréquence cardiaque."
            ) {
                Picker("Sexe", selection: sexBinding) {
                    Text("Non renseigné").tag(AthleteSex?.none)
                    ForEach(AthleteSex.allCases) { sex in
                        Text(sex.label).tag(AthleteSex?.some(sex))
                    }
                }
                LabeledContent("Taille") {
                    HStack(spacing: SharpitSpacing.xxs) {
                        TextField("178", text: $form.heightCm)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("cm")
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                if let error = form.error(for: .heightCm) {
                    Text(error)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
                if form.birthDate != nil {
                    DatePicker(
                        "Date de naissance",
                        selection: birthDateBinding,
                        in: Self.birthDateRange,
                        displayedComponents: .date
                    )
                    .environment(\.locale, SharpitLocale.french)
                } else {
                    Button("Ajouter ta date de naissance") {
                        form.birthDate = Self.defaultBirthDate
                        scheduleProfileSave()
                    }
                }
                LabeledContent("Âge", value: AccountAge.years(birthDate: form.birthDate).map { "\($0) ans" } ?? "—")
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .disabled(!hasLoaded)
        .redacted(reason: hasLoaded ? [] : .placeholder)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Compte")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving { ProgressView().controlSize(.small) }
            }
        }
        .task {
            firstName = clerk.user?.firstName ?? ""
            lastName = clerk.user?.lastName ?? ""
            await store.load()
            form = ProfileFormState(profile: store.profile)
            hasLoaded = true
        }
        .onChange(of: firstName) { _, _ in scheduleNameSave() }
        .onChange(of: lastName) { _, _ in scheduleNameSave() }
        .onChange(of: form.heightCm) { _, _ in scheduleProfileSave() }
        .sheet(isPresented: $isEditingAccount) { SharpitUserProfileSheet() }
    }

    private var sexBinding: Binding<AthleteSex?> {
        Binding(
            get: { store.profile.sex },
            set: { sex in
                var patch = AthleteProfilePatch()
                patch.setSex(sex)
                Task { await store.save(patch) }
            }
        )
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { form.birthDate ?? Self.defaultBirthDate },
            set: { date in
                form.birthDate = date
                scheduleProfileSave()
            }
        )
    }

    /// Names go to Clerk a moment after the last keystroke, trimmed; an unchanged name sends
    /// nothing.
    private func scheduleNameSave() {
        guard hasLoaded else { return }
        nameSave?.cancel()
        nameSave = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let user = clerk.user else { return }
            let first = firstName.trimmingCharacters(in: .whitespaces)
            let last = lastName.trimmingCharacters(in: .whitespaces)
            guard first != (user.firstName ?? "") || last != (user.lastName ?? "") else { return }
            do {
                _ = try await user.update(.init(firstName: first, lastName: last))
            } catch {
                toastCenter?.show("Nom non enregistré. Réessaie.", symbol: "exclamationmark.triangle.fill", tone: .error)
            }
        }
    }

    /// Height and birth date, saved together once the typing stops and only when they read.
    private func scheduleProfileSave() {
        guard hasLoaded else { return }
        profileSave?.cancel()
        profileSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, form.error(for: .heightCm) == nil else { return }
            var patch = AthleteProfilePatch()
            patch.setIfChanged(.heightCm, int: ProfileFieldFormat.parseInteger(form.heightCm), was: store.profile.heightCm)
            if !ProfileFieldFormat.isSameDay(form.birthDate, store.profile.birthDate) {
                patch.set(.birthDate, string: ProfileFieldFormat.isoDay(form.birthDate))
            }
            guard !patch.isEmpty else { return }
            if await store.save(patch) == false, let error = store.saveError {
                toastCenter?.show(error, symbol: "exclamationmark.triangle.fill", tone: .error)
            }
        }
    }

    private static let birthDateRange: ClosedRange<Date> = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: 1920, month: 1, day: 1))!...Date.now
    }()

    private static let defaultBirthDate: Date = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: 1990, month: 1, day: 1)) ?? .now
    }()
}

nonisolated enum AccountAge {
    /// Whole years since the birth date, as the web's profile shows them.
    static func years(birthDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let birthDate, birthDate < now else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: now).year
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Notifications

/// Which pushes the athlete wants (`notificationPrefs` on the profile). Each switch saves on the
/// tap and sends only itself — the server merges it over what it stores. Whether iOS lets
/// SharpIt notify at all is the master switch on Paramètres.
struct NotificationPrefsView: View {
    @State private var store: AthleteProfileStore

    init(profileClient: any AthleteProfileServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: AthleteProfileStore(client: profileClient, tokenProvider: tokenProvider))
    }

    private var prefs: V1NotificationPrefs {
        store.profile.notificationPrefs ?? V1NotificationPrefs()
    }

    var body: some View {
        List {
            Section(
                eyebrow: "Ce que SharpIt t'envoie",
                footer: "Seul le verdict du matin est envoyé aujourd'hui. Tes autres choix seront respectés dès que ces notifications arriveront."
            ) {
                toggle("Verdict du matin", detail: "Ta lecture du jour, une fois ta nuit synchronisée.", symbol: "sun.horizon", key: "morningVerdict", value: prefs.morningVerdict)
                toggle("Bilan de la semaine", detail: "Le résumé de ta semaine d'entraînement.", symbol: "calendar", key: "weeklyReview", value: prefs.weeklyReview)
                toggle("Rappel de séance", detail: "Avant une séance prévue.", symbol: "figure.run", key: "sessionReminder", value: prefs.sessionReminder)
                toggle("Alertes de synchronisation", detail: "Quand une source doit être reconnectée.", symbol: "arrow.triangle.2.circlepath", key: "syncAlerts", value: prefs.syncAlerts)
            }
            .sharpitListRows()

            if let error = store.saveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
                .listRowBackground(Color.clear)
            }
        }
        .sharpitGroupedList()
        .disabled(store.phase != .loaded)
        .redacted(reason: store.phase == .loaded ? [] : .placeholder)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
    }

    private func toggle(_ title: String, detail: String, symbol: String, key: String, value: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { on in
                var patch = AthleteProfilePatch()
                patch.setNotificationPrefs([key: .bool(on)])
                Task { await store.save(patch) }
            }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SharpitTypography.bodyEmphasis)
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            } icon: {
                SharpitRowIcon(symbol: symbol)
            }
        }
        .tint(SharpitColor.primary)
    }
}
