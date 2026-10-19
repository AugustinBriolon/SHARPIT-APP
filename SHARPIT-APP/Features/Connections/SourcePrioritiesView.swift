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
        .navigationBarTitleDisplayMode(.inline)
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
                    ForEach(sourceClass.providers.filter { store.isConnected($0.id) }) { provider in
                        row(provider, in: sourceClass)
                        writeCalendarRow(provider, in: sourceClass)
                    }
                } header: {
                    SharpitEyebrow(sourceClass.label)
                } footer: {
                    SharpitListFooter(footer(for: sourceClass))
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
            return String(localized: "\(base) Touche le nom pour choisir la source principale ; le commutateur active ou coupe la source.")
        }
        if store.connectedCount(in: sourceClass.id) > 1 {
            return String(localized: "\(base) Active au moins deux sources pour en choisir une principale.")
        }
        return base
    }

    private func row(_ provider: V1SourceClass.Provider, in sourceClass: V1SourceClass) -> some View {
        let isEnabled = store.isEnabled(provider.id, in: sourceClass.id)
        let isPrimary = store.isPrimary(provider.id, in: sourceClass.id)
        let choosesPrimary = store.canChoosePrimary(in: sourceClass.id) && isEnabled
        return HStack(spacing: SharpitSpacing.sm) {
            if let logo = ProviderLogo.Provider(integrationId: provider.id) {
                ProviderLogo(provider: logo)
            }
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    guard choosesPrimary else { return }
                    Task { await store.setPrimary(provider.id, in: sourceClass.id) }
                } label: {
                    HStack(spacing: SharpitSpacing.xs) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.foreground)
                            if choosesPrimary {
                                Text(isPrimary ? String(localized: "Principale") : String(localized: "Choisir comme principale"))
                                    .font(SharpitTypography.meta.weight(isPrimary ? .semibold : .regular))
                                    .foregroundStyle(isPrimary ? SharpitColor.primary : SharpitColor.mutedForeground)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if choosesPrimary {
                            // Keep the mark beside the copy — a `Label` in a stretched row
                            // pushes the glyph and the title to opposite edges.
                            Image(systemName: isPrimary ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .foregroundStyle(isPrimary ? SharpitColor.primary : SharpitColor.mutedForeground)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!choosesPrimary)
                .accessibilityAddTraits(isPrimary ? [.isSelected] : [])
                .accessibilityHint(choosesPrimary && !isPrimary ? String(localized: "En fait la source principale") : "")
                .accessibilityLabel(
                    choosesPrimary
                        ? "\(provider.name), \(isPrimary ? "principale" : "pas principale")"
                        : provider.name
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            .tint(SharpitColor.primary)
        }
        .padding(.vertical, SharpitSpacing.xxs)
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
                .foregroundStyle(isProblem ? SharpitColor.signalRisk : SharpitColor.mutedForeground)
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
