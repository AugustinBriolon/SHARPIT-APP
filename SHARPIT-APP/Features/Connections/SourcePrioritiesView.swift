import SwiftUI

/// Paramètres › Sources de données › Priorités: per data class, which connected sources feed it
/// and which one is the primary (SHARPIT ADR-054). The primary is the source of truth; the others
/// fill what it lacks. A class only one source can feed shows it, with nothing to choose.
struct SourcePrioritiesView: View {
    @State private var store: SourcePrefsStore
    private let googleClient: any GoogleCalendarsServing
    private let tokenProvider: () async throws -> String
    @State private var googleWriteTargetName: String?
    @State private var googleWriteTargetHint: String?
    @State private var appleWriteCalendarName: String?
    private let appleCalendar: AppleCalendarSource?

    init(
        client: any SourcePrefsServing = SharpitClient(),
        googleClient: any GoogleCalendarsServing = GoogleCalendarsClient(),
        tokenProvider: @escaping () async throws -> String,
        appleCalendar: AppleCalendarSource? = nil
    ) {
        _store = State(initialValue: SourcePrefsStore(client: client, tokenProvider: tokenProvider))
        self.googleClient = googleClient
        self.tokenProvider = tokenProvider
        self.appleCalendar = appleCalendar
    }

    var body: some View {
        Group {
            switch store.phase {
            case .failed(let message):
                SharpitStateMessage.failed(message) { Task { await store.load() } }
            case .loading, .loaded:
                list
            }
        }
        .navigationTitle("Priorités")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await store.load()
            resyncAppleCalendarLink()
            await refreshGoogleWriteTarget()
            await refreshAppleWriteCalendarName()
        }
    }

    private var list: some View {
        List {
            ForEach(store.classes) { sourceClass in
                Section {
                    let connected = sourceClass.providers.filter { store.isConnected($0.id) }
                    ForEach(connected) { provider in
                        row(provider, in: sourceClass)
                        writeCalendarRow(provider, in: sourceClass)
                    }
                    primaryRow(among: connected, in: sourceClass)
                } header: {
                    SharpitEyebrow(sourceClass.label).unredacted()
                } footer: {
                    SharpitListFooter(footer(for: sourceClass)).unredacted()
                }
                .sharpitListRows()
            }
        }
        .sharpitGroupedList()
        .redacted(reason: store.phase == .loading ? .placeholder : [])
        .animation(SharpitMotion.selection, value: store.prefs)
    }

    private func footer(for sourceClass: V1SourceClass) -> String {
        let base = sourceClass.description
        if store.canChoosePrimary(in: sourceClass.id) {
            return String(localized: "\(base) La source principale fait foi ; les autres complètent ce qui lui manque.")
        }
        if store.connectedCount(in: sourceClass.id) > 1 {
            return String(localized: "\(base) Active au moins deux sources pour en choisir une principale.")
        }
        return base
    }

    /// A source: its switch says whether it feeds the class — nothing else to tap on the line.
    private func row(_ provider: V1SourceClass.Provider, in sourceClass: V1SourceClass) -> some View {
        let isEnabled = store.isEnabled(provider.id, in: sourceClass.id)
        let isPrimary = store.canChoosePrimary(in: sourceClass.id) && isEnabled && store.isPrimary(provider.id, in: sourceClass.id)
        return HStack(spacing: SharpitSpacing.sm) {
            if let logo = ProviderLogo.Provider(integrationId: provider.id) {
                ProviderLogo(provider: logo)
            }
            Text(provider.name)
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                .foregroundStyle(SharpitColor.foreground)
            if isPrimary {
                CliniqueStatusPill(String(localized: "Principale"), status: .good)
            }
            Spacer(minLength: SharpitSpacing.xs)
            Toggle(
                String(localized: "Utiliser \(provider.name)"),
                isOn: Binding(
                    get: { isEnabled },
                    set: { on in
                        Task {
                            await setProviderEnabled(on, provider: provider, in: sourceClass.id)
                        }
                    }
                )
            )
            .labelsHidden()
        }
        .padding(.vertical, SharpitSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    /// Which of the sources switched on leads: one line, one menu — only when two or more are on.
    @ViewBuilder
    private func primaryRow(among providers: [V1SourceClass.Provider], in sourceClass: V1SourceClass) -> some View {
        let enabled = providers.filter { store.isEnabled($0.id, in: sourceClass.id) }
        if store.canChoosePrimary(in: sourceClass.id), enabled.count > 1 {
            let current = enabled.first { store.isPrimary($0.id, in: sourceClass.id) }
            HStack(spacing: SharpitSpacing.sm) {
                Text("Source principale")
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: SharpitSpacing.xs)
                Menu {
                    Picker("Source principale", selection: Binding(
                        get: { current?.id ?? "" },
                        set: { id in Task { await store.setPrimary(id, in: sourceClass.id) } }
                    )) {
                        ForEach(enabled) { provider in Text(provider.name).tag(provider.id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(current?.name ?? String(localized: "Choisir"))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.slate)
                }
            }
        }
    }

    /// Its own row: inside the provider row, beside its button and switch, the link was a hard target.
    @ViewBuilder
    private func writeCalendarRow(_ provider: V1SourceClass.Provider, in sourceClass: V1SourceClass) -> some View {
        if showsGoogleWriteCalendarPicker(in: sourceClass, provider: provider) {
            NavigationLink {
                GoogleCalendarPickerView(tokenProvider: tokenProvider, client: googleClient) {
                    Task { await refreshGoogleWriteTarget() }
                }
            } label: {
                writeCalendarLabel(
                    String(localized: "Calendrier Google"),
                    value: googleWriteCalendarSubtitle,
                    isProblem: googleWriteTargetHint != nil
                )
            }
        } else if showsAppleWriteCalendarPicker(in: sourceClass, provider: provider) {
            NavigationLink {
                AppleCalendarPickerView {
                    Task { await refreshAppleWriteCalendarName() }
                }
            } label: {
                writeCalendarLabel(String(localized: "Calendrier de l'iPhone"), value: appleWriteCalendarSubtitle, isProblem: false)
            }
        }
    }

    private func writeCalendarLabel(_ title: String, value: String, isProblem: Bool) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(isProblem ? SharpitColor.signalRisk : SharpitColor.slate)
        } label: {
            Text(title)
                .foregroundStyle(SharpitColor.foreground)
        }
        .font(SharpitTypography.meta)
    }

    private func showsGoogleWriteCalendarPicker(
        in sourceClass: V1SourceClass,
        provider: V1SourceClass.Provider
    ) -> Bool {
        sourceClass.id == "calendar" && provider.id == "google" && store.isConnected("google")
    }

    private func showsAppleWriteCalendarPicker(
        in sourceClass: V1SourceClass,
        provider: V1SourceClass.Provider
    ) -> Bool {
        sourceClass.id == "calendar"
            && provider.id == AppleCalendarSync.providerId
            && store.isConnected(AppleCalendarSync.providerId)
    }

    private var googleWriteCalendarSubtitle: String {
        googleWriteTargetHint ?? googleWriteTargetName ?? String(localized: "Choisir un calendrier")
    }

    private var appleWriteCalendarSubtitle: String {
        appleWriteCalendarName ?? String(localized: "Choisir un calendrier")
    }

    private func resyncAppleCalendarLink() {
        appleCalendar?.syncLinkedFromServer(store.isConnected(AppleCalendarSync.providerId))
    }

    private func setProviderEnabled(_ on: Bool, provider: V1SourceClass.Provider, in classId: String) async {
        let isAppleCalendar = provider.id == AppleCalendarSync.providerId && classId == "calendar"
        if isAppleCalendar {
            if on {
                if let appleCalendar {
                    await appleCalendar.enable(token: tokenProvider)
                    guard appleCalendar.isLinked else { return }
                } else {
                    _ = await AppleCalendarSync.shared.enable()
                }
                store.patchConnected(AppleCalendarSync.providerId, linked: true)
            } else {
                if let appleCalendar {
                    await appleCalendar.disable(token: tokenProvider)
                    guard !appleCalendar.isLinked else { return }
                } else {
                    AppleCalendarSync.shared.disable()
                }
                store.patchConnected(AppleCalendarSync.providerId, linked: false)
            }
        }
        await store.setEnabled(provider.id, in: classId, on)
        if isAppleCalendar { return }
        resyncAppleCalendarLink()
    }

    private func refreshAppleWriteCalendarName() async {
        guard store.isConnected(AppleCalendarSync.providerId) else {
            appleWriteCalendarName = nil
            return
        }
        let sync = AppleCalendarSync.shared
        if await sync.requestAccess() {
            appleWriteCalendarName = sync.selectedWriteCalendarTitle()
        } else if let id = sync.writeCalendarIdentifier {
            appleWriteCalendarName = id
        } else {
            appleWriteCalendarName = nil
        }
    }

    private func refreshGoogleWriteTarget() async {
        guard store.isConnected("google") else {
            googleWriteTargetName = nil
            googleWriteTargetHint = nil
            return
        }
        do {
            let token = try await tokenProvider()
            let calendars = try await googleClient.googleCalendars(token: token)
            googleWriteTargetName = calendars.first(where: \.isTarget)?.summary
            googleWriteTargetHint = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch SharpitAPIError.googleNeedsReconnect(let message) {
            googleWriteTargetName = nil
            googleWriteTargetHint = message
        } catch {
            if googleWriteTargetName == nil {
                googleWriteTargetHint = String(localized: "Impossible de charger le calendrier")
            }
        }
    }
}
