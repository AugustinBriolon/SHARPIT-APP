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
    @Environment(\.modelContext) private var modelContext
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var store: AthleteProfileStore
    @State private var form = ProfileFormState()
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var hasLoaded = false
    @State private var nameSave: Task<Void, Never>?
    @State private var profileSave: Task<Void, Never>?
    @State private var isEditingAccount = false
    @State private var isConfirmingSignOut = false
    @Environment(ProStore.self) private var pro: ProStore?

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
            // Who is signed in, on one line as the system's own settings open: the face, the name
            // and the e-mail, opening Clerk's sheet for the photo, the e-mail and the password.
            Section {
                Button { isEditingAccount = true } label: {
                    AccountLine(firstName: firstName, lastName: lastName)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre la photo, l'e-mail et le mot de passe")
                NavigationLink(value: SettingsRoute.pro) {
                    SharpitSettingsLabel(
                        title: String(localized: "Abonnement"),
                        detail: isPro || pro?.pro?.subscription != nil
                            ? ProReadout.status(pro?.pro?.subscription, isPro: isPro)
                            : String(localized: "Découvrir"),
                        symbol: "sparkles"
                    )
                }
            }
            .sharpitListRows()

            Section(
                eyebrow: String(localized: "Identité"),
                footer: String(localized: "Ton prénom sert à te saluer, ton nom reste sur ton compte.")
            ) {
                AccountFieldRow(title: String(localized: "Prénom"), symbol: "person") {
                    TextField("Prénom", text: $firstName)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                }
                AccountFieldRow(title: String(localized: "Nom"), symbol: "person.text.rectangle") {
                    TextField("Nom", text: $lastName)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.familyName)
                        .submitLabel(.done)
                }
            }
            .sharpitListRows()

            Section(
                eyebrow: String(localized: "Profil"),
                footer: String(localized: "Le sexe, la taille et l'âge servent à l'âge biologique et aux normes de fréquence cardiaque.")
            ) {
                Picker(selection: sexBinding) {
                    Text("Non renseigné").tag(AthleteSex?.none)
                    ForEach(AthleteSex.allCases) { sex in
                        Text(sex.label).tag(AthleteSex?.some(sex))
                    }
                } label: {
                    AccountRowTitle(title: String(localized: "Sexe"), symbol: "figure.stand")
                }
                .pickerStyle(.menu)
                .tint(SharpitColor.slate)
                AccountFieldRow(title: String(localized: "Taille"), symbol: "ruler") {
                    HStack(spacing: SharpitSpacing.xxs) {
                        TextField("178", text: $form.heightCm)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("cm")
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
                if let error = form.error(for: .heightCm) {
                    Text(error)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
                if form.birthDate != nil {
                    // The age reads under the label it derives from, not on a read-only row of its own.
                    DatePicker(selection: birthDateBinding, in: Self.birthDateRange, displayedComponents: .date) {
                        AccountRowTitle(
                            title: String(localized: "Date de naissance"),
                            symbol: "calendar",
                            detail: AccountAge.label(birthDate: form.birthDate)
                        )
                    }
                    .environment(\.locale, SharpitLocale.current)
                } else {
                    Button {
                        form.birthDate = Self.defaultBirthDate
                        scheduleProfileSave()
                    } label: {
                        AccountRowTitle(title: String(localized: "Ajouter ta date de naissance"), symbol: "calendar")
                    }
                    .buttonStyle(.plain)
                }
            }
            .sharpitListRows()

            Section {
                Button(role: .destructive) { isConfirmingSignOut = true } label: {
                    AccountRowTitle(
                        title: String(localized: "Se déconnecter"),
                        symbol: "rectangle.portrait.and.arrow.right",
                        tone: SharpitColor.signalRisk
                    )
                }
                .buttonStyle(.plain)
            } footer: {
                SharpitListFooter(String(localized: "Tes données restent sur ton compte. Pour le supprimer, va dans Confidentialité & conditions."))
            }
            .sharpitListRows()
        }
        .confirmationDialog("Se déconnecter ?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive, action: signOut)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les données gardées sur cet iPhone sont effacées. Elles reviennent à ta prochaine connexion.")
        }
        .sharpitGroupedList()
        // The rows are known before the profile is: they stand, and wait to be edited
        // (`docs/adr/0038`). No redaction.
        .disabled(!hasLoaded)
        .scrollDismissesKeyboard(.interactively)
        // The name of the row that opens it, on the large title every settings page takes.
        .navigationTitle("Ton profil")
        .navigationBarTitleDisplayMode(.large)
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

    private var isPro: Bool { pro?.pro?.isPro ?? store.profile.isPro }

    /// Same wipe as account delete: health cache, SwiftData and disk stay tied to the account
    /// that wrote them — never paint the next sign-in from them.
    private func signOut() {
        LocalAccountData.erase(context: modelContext)
        Task { try? await clerk.auth.signOut() }
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
                toastCenter?.show(String(localized: "Nom non enregistré. Réessaie."), symbol: "exclamationmark.triangle.fill", tone: .error)
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

/// Who is signed in, as one line: the face, the name as typed over the e-mail, and a chevron,
/// since the line opens Clerk's sheet.
private struct AccountLine: View {
    let firstName: String
    let lastName: String

    @Environment(Clerk.self) private var clerk: Clerk?
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 44

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            if clerk != nil { AccountAvatar(size: avatarSize) }
            VStack(alignment: .leading, spacing: 2) {
                Text(AccountDisplayName.from(first: firstName, last: lastName) ?? String(localized: "Ton compte"))
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                if let email = clerk?.user?.primaryEmailAddress?.emailAddress {
                    Text(email)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SharpitColor.slate.opacity(0.5))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A profile row's leading half: the glyph in the settings rows' column, the title, and under it
/// what derives from the value (the age under the birth date).
private struct AccountRowTitle: View {
    let title: String
    let symbol: String
    var detail: String?
    var tone: Color = SharpitColor.foreground

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(tone)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                    .foregroundStyle(tone)
                if let detail {
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// A profile row typed in place: its title on the left, the field at the trailing edge.
private struct AccountFieldRow<Field: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let field: Field

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            AccountRowTitle(title: title, symbol: symbol)
            field
                .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.slate)
        }
    }
}

nonisolated enum AccountAge {
    /// Whole years since the birth date, as the web's profile shows them.
    static func years(birthDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let birthDate, birthDate < now else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: now).year
    }

    /// « 36 ans », under the birth date it comes from; nil while none is set.
    static func label(birthDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        years(birthDate: birthDate, now: now, calendar: calendar).map { String(localized: "\($0) ans") }
    }
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
            Section(eyebrow: String(localized: "Sur cet appareil"), footer: masterFooter) {
                Toggle(isOn: masterBinding) {
                    Label {
                        Text("Autoriser les notifications")
                            .font(SharpitTypography.bodyEmphasis)
                    } icon: {
                        SharpitRowIcon.tile("bell.badge")
                    }
                }
                .tint(SharpitColor.primary)
            }
            .sharpitListRows()

            kinds

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
        .navigationBarTitleDisplayMode(.large)
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
            return String(localized: "Refusées dans les réglages d'iOS : touche l'interrupteur pour les ouvrir.")
        }
        return isOn
            ? String(localized: "Choisis ci-dessous ce que SharpIt envoie sur cet appareil.")
            : String(localized: "Cet appareil ne reçoit plus rien. Tes choix sont gardés pour quand tu les réactives.")
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
                    await refreshDayCheckIns()
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

    /// Callers: NotificationsSettings. API: dayCheckIns. User: fix all — P2 check-ins.
    private func refreshDayCheckIns() async {
        await DayCheckInReminderScheduler.shared.refresh(
            isEnabledOnPhone: isOn,
            profiles: profileClient,
            tokenProvider: tokenProvider
        )
    }

    private var kinds: some View {
        Section(
            eyebrow: String(localized: "Ce que SharpIt t'envoie"),
            footer: String(localized: "Les rappels de séance partent de cet appareil, depuis ton plan : une heure avant, ou à 7 h 30 le jour même si la séance n'a pas d'heure.")
        ) {
            toggle(String(localized: "Verdict du matin"), detail: String(localized: "Ta lecture du jour, une fois ta nuit synchronisée."), symbol: "sun.horizon", key: "morningVerdict", value: prefs.morningVerdict)
            toggle(String(localized: "Bilan de la semaine"), detail: String(localized: "Le résumé de ta semaine d'entraînement."), symbol: "calendar", key: "weeklyReview", value: prefs.weeklyReview)
            toggle(String(localized: "Rappel de séance"), detail: String(localized: "Une heure avant une séance prévue."), symbol: "figure.run", key: "sessionReminder", value: prefs.sessionReminder)
            toggle(String(localized: "Séance faite"), detail: String(localized: "Après une séance synchronisée : sa part du plan et la suivante."), symbol: "checkmark.seal", key: "sessionDone", value: prefs.sessionDone)
            toggle(String(localized: "Cible du jour"), detail: String(localized: "Quand ton effort entre dans la bande cible du jour."), symbol: "target", key: "targetStrain", value: prefs.targetStrain)
            toggle(String(localized: "Check-ins du jour"), detail: String(localized: "Rappels locaux : hydratation, humeur, caféine."), symbol: "checklist", key: "dayCheckIns", value: prefs.dayCheckIns)
            toggle(String(localized: "Séance manquée"), detail: String(localized: "Le lendemain, pour réorganiser ta semaine en un geste."), symbol: "arrow.uturn.forward", key: "missedSession", value: prefs.missedSession)
            toggle(String(localized: "Alertes de synchronisation"), detail: String(localized: "Quand une source doit être reconnectée."), symbol: "arrow.triangle.2.circlepath", key: "syncAlerts", value: prefs.syncAlerts)
            Toggle(isOn: Binding(
                get: { CoachReplyLiveActivityPreference.isEnabled },
                set: { CoachReplyLiveActivityPreference.setEnabled($0) }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Activity coach")
                            .font(SharpitTypography.bodyEmphasis)
                        Text("Sur l'écran verrouillé pendant que le coach répond.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                    }
                } icon: {
                    SharpitRowIcon.tile("lock.iphone")
                }
            }
            .tint(SharpitColor.primary)
            Toggle(isOn: Binding(
                get: { GuidedStrengthRestLiveActivityPreference.isEnabled },
                set: { GuidedStrengthRestLiveActivityPreference.setEnabled($0) }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Activity muscu")
                            .font(SharpitTypography.bodyEmphasis)
                        Text("Séance et timer de repos sur l'écran verrouillé.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                    }
                } icon: {
                    SharpitRowIcon.tile("timer")
                }
            }
            .tint(SharpitColor.primary)
            Toggle(isOn: Binding(
                get: { GuidedHeartRatePreference.isEnabled },
                set: { GuidedHeartRatePreference.setEnabled($0) }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capteur FC Bluetooth")
                            .font(SharpitTypography.bodyEmphasis)
                        Text("Ou tape « FC » en haut pendant un suivi muscu pour choisir le capteur BLE.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                    }
                } icon: {
                    SharpitRowIcon.tile("heart.fill")
                }
            }
            .tint(SharpitColor.primary)
        }
        .sharpitListRows()
        // The kinds are the app's own list: named at once, switched once the profile is read
        // (`docs/adr/0038`). A failure says so below with a retry.
        .disabled(store.phase != .loaded)
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
                if key == "dayCheckIns" { Task { await store.settle(); await refreshDayCheckIns() } }
            }
        )) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SharpitTypography.bodyEmphasis)
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
            } icon: {
                SharpitRowIcon.tile(symbol)
            }
        }
        .tint(SharpitColor.primary)
    }
}
