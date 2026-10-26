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
            Section {
                AccountHeader(
                    firstName: firstName,
                    lastName: lastName,
                    isPro: isPro,
                    onEditPhoto: { isEditingAccount = true }
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // The header already says who and which tier: the rows only open what changes them.
            Section(eyebrow: String(localized: "Connexion")) {
                Button { isEditingAccount = true } label: {
                    SharpitSettingsLabel(
                        symbol: "lock",
                        title: String(localized: "Photo et sécurité"),
                        detail: String(localized: "E-mail et mot de passe")
                    )
                }
                .buttonStyle(.plain)
                NavigationLink(value: SettingsRoute.pro) {
                    SharpitSettingsLabel(
                        symbol: "sparkle",
                        title: String(localized: "Abonnement"),
                        detail: isPro || pro?.pro?.subscription != nil
                            ? ProReadout.status(pro?.pro?.subscription, isPro: isPro)
                            : String(localized: "Découvrir SharpIt Pro")
                    )
                }
            }
            .sharpitListRows()

            Section(
                eyebrow: String(localized: "Identité"),
                footer: String(localized: "Ton prénom sert à te saluer, ton nom reste sur ton compte.")
            ) {
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
                eyebrow: String(localized: "Profil"),
                footer: String(localized: "Le sexe, la taille et l'âge servent à l'âge biologique et aux normes de fréquence cardiaque.")
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
                    // The age reads under the label it derives from, not on a read-only row of its own.
                    DatePicker(selection: birthDateBinding, in: Self.birthDateRange, displayedComponents: .date) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Date de naissance")
                            if let age = AccountAge.label(birthDate: form.birthDate) {
                                Text(age)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                    .environment(\.locale, SharpitLocale.current)
                } else {
                    Button("Ajouter ta date de naissance") {
                        form.birthDate = Self.defaultBirthDate
                        scheduleProfileSave()
                    }
                }
            }
            .sharpitListRows()

            Section {
                Button(role: .destructive) { isConfirmingSignOut = true } label: {
                    Text("Se déconnecter").frame(maxWidth: .infinity)
                }
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

/// The page's top: the face (a tap opens Clerk's photo editor), the name as typed below, the
/// e-mail and the tier.
private struct AccountHeader: View {
    let firstName: String
    let lastName: String
    let isPro: Bool
    let onEditPhoto: () -> Void

    @Environment(Clerk.self) private var clerk
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 96

    var body: some View {
        VStack(spacing: SharpitSpacing.sm) {
            Button(action: onEditPhoto) {
                AccountAvatar(size: avatarSize)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SharpitColor.inkSurfaceForeground)
                            .frame(width: 28, height: 28)
                            .background(SharpitColor.inkSurface, in: Circle())
                    }
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityLabel("Changer la photo")

            VStack(spacing: SharpitSpacing.xxs) {
                Text(AccountDisplayName.from(first: firstName, last: lastName) ?? String(localized: "Ton compte"))
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                if let email = clerk.user?.primaryEmailAddress?.emailAddress {
                    Text(email)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
            }
            SharpitPill(isPro ? String(localized: "Pro") : String(localized: "Gratuit"), style: isPro ? .lime : .neutral)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SharpitSpacing.md)
        .accessibilityElement(children: .contain)
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
                            .foregroundStyle(SharpitColor.mutedForeground)
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
                            .foregroundStyle(SharpitColor.mutedForeground)
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
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                } icon: {
                    SharpitRowIcon.tile("heart.fill")
                }
            }
            .tint(SharpitColor.primary)
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
                if key == "dayCheckIns" { Task { await store.settle(); await refreshDayCheckIns() } }
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
                SharpitRowIcon.tile(symbol)
            }
        }
        .tint(SharpitColor.primary)
    }
}
