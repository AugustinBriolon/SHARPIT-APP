import ClerkKit
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

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

            Section {
                Button(role: .destructive) {
                    // Signed out, the home screen shows no one's day.
                    WidgetSnapshotPublisher.erase()
                    Task { try? await clerk.auth.signOut() }
                } label: {
                    Text("Se déconnecter").frame(maxWidth: .infinity)
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .disabled(!hasLoaded)
        .redacted(reason: hasLoaded ? [] : .placeholder)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Compte")
        .navigationBarTitleDisplayMode(.inline)
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
                store.save(patch)
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
            store.save(patch)
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
    @State private var push = PushNotificationManager.shared
    @State private var notificationStatus: UNAuthorizationStatus?
    @Environment(\.scenePhase) private var scenePhase
    private let tokenProvider: () async throws -> String
    private let profileClient: any AthleteProfileServing

    /// The context paints the profile read last time at once: without it, every opening showed
    /// the switches as placeholders until the network answered — and for good when it did not.
    init(
        profileClient: any AthleteProfileServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        _store = State(initialValue: AthleteProfileStore(
            client: profileClient,
            tokenProvider: tokenProvider,
            modelContext: modelContext
        ))
        self.tokenProvider = tokenProvider
        self.profileClient = profileClient
    }

    private var isOn: Bool { push.isEnabledByAthlete && notificationStatus != .denied }

    private var prefs: V1NotificationPrefs {
        store.profile.notificationPrefs ?? V1NotificationPrefs()
    }

    var body: some View {
        List {
            Section(eyebrow: "Sur cet iPhone", footer: masterFooter) {
                Toggle(isOn: masterBinding) {
                    Label {
                        Text("Autoriser les notifications")
                            .font(SharpitTypography.bodyEmphasis)
                    } icon: {
                        SharpitRowIcon(symbol: "bell.badge")
                    }
                }
                .tint(SharpitColor.primary)
            }
            .sharpitListRows()

            if isOn {
                kinds
            }

            if case .failed(let message) = store.phase {
                Section {
                    Button {
                        Task { await store.load() }
                    } label: {
                        Label("\(message) Réessayer", systemImage: "arrow.clockwise")
                            .font(SharpitTypography.meta)
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .sharpitGroupedList()
        .animation(SharpitMotion.reveal, value: isOn)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshStatus()
            await store.load()
        }
        // Back from iOS's own settings, where a refusal is lifted.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
    }

    private var masterFooter: String {
        if notificationStatus == .denied {
            return "Refusées dans les réglages d'iOS : touche l'interrupteur pour les ouvrir."
        }
        return isOn
            ? "Choisis ci-dessous ce que SharpIt envoie sur cet iPhone."
            : "Cet iPhone ne reçoit plus rien. Tes choix sont gardés pour quand tu les réactives."
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { on in
                Task {
                    if on, notificationStatus == .denied {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            await UIApplication.shared.open(url)
                        }
                        return
                    }
                    await push.setEnabled(on, tokenProvider: tokenProvider)
                    await refreshStatus()
                    await refreshSessionReminders()
                }
            }
        )
    }

    private func refreshStatus() async {
        notificationStatus = await push.authorizationStatus()
    }

    /// Session reminders are scheduled on the phone: a switch changed here applies at once.
    private func refreshSessionReminders() async {
        await SessionReminderScheduler.shared.refresh(
            isEnabledOnPhone: isOn,
            profiles: profileClient,
            plan: PlannedSessionClient(),
            tokenProvider: tokenProvider
        )
    }

    private var kinds: some View {
        Section(
            eyebrow: "Ce que SharpIt t'envoie",
            footer: "Les rappels de séance partent de cet iPhone, depuis ton plan : une heure avant, ou à 7 h 30 le jour même si la séance n'a pas d'heure."
        ) {
            toggle("Verdict du matin", detail: "Ta lecture du jour, une fois ta nuit synchronisée.", symbol: "sun.horizon", key: "morningVerdict", value: prefs.morningVerdict)
            toggle("Bilan de la semaine", detail: "Le résumé de ta semaine d'entraînement.", symbol: "calendar", key: "weeklyReview", value: prefs.weeklyReview)
            toggle("Rappel de séance", detail: "Une heure avant une séance prévue.", symbol: "figure.run", key: "sessionReminder", value: prefs.sessionReminder)
            toggle("Séance comptée", detail: "Après une séance synchronisée : sa part du plan et la suivante.", symbol: "checkmark.seal", key: "sessionDone", value: prefs.sessionDone)
            toggle("Alertes de synchronisation", detail: "Quand une source doit être reconnectée.", symbol: "arrow.triangle.2.circlepath", key: "syncAlerts", value: prefs.syncAlerts)
        }
        .sharpitListRows()
        // Placeholders only while the very first read is under way; a failure says so below
        // with a retry instead of leaving the switches greyed out.
        .disabled(store.phase != .loaded)
        .redacted(reason: store.phase == .loading ? .placeholder : [])
        .transition(.opacity)
    }

    private func toggle(_ title: String, detail: String, symbol: String, key: String, value: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { on in
                var patch = AthleteProfilePatch()
                patch.setNotificationPrefs([key: .bool(on)])
                store.save(patch)
                // The scheduler reads the server's prefs, so it waits for the write to land.
                if key == "sessionReminder" { Task { await store.settle(); await refreshSessionReminders() } }
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
