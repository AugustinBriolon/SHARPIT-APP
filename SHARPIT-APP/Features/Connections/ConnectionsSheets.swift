import SwiftUI

/// The sheet a connected source opens: what it brings, how it stands, and the way out. The
/// confirmation lives here so the sheet and the question it asks leave together.
struct SourceManageSheet: View {
    let source: ManagedSource
    let status: ConnectionsReadout.Line
    /// The picker for the calendar SharpIt writes the plan into, for the calendar sources.
    var calendarPicker: AnyView? = nil
    /// Garmin's: a new key replaces the stored one (`GarminKeySheet`).
    var onReplaceKey: (() -> Void)? = nil
    let onDisconnect: () -> Void

    @State private var confirming = false
    @State private var pickingCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            HStack(spacing: SharpitSpacing.sm) {
                ProviderLogo(provider: source.logo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(status.text)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(status.isProblem ? SharpitColor.signalRisk : SharpitColor.mutedForeground)
                }
            }
            Text(source.benefit)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if calendarPicker != nil {
                Button { pickingCalendar = true } label: {
                    HStack {
                        Label("Calendrier des séances", systemImage: "calendar")
                            .font(SharpitTypography.bodyEmphasis)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(SharpitColor.foreground)
                    .padding(.vertical, SharpitSpacing.xs)
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityHint("Choisis où SharpIt écrit tes séances")
            }
            if let onReplaceKey {
                SharpitPrimaryButton(title: String(localized: "Remplacer la clé"), style: .secondary, action: onReplaceKey)
            }
            SharpitPrimaryButton(title: source.disconnectLabel, style: .secondary) { confirming = true }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(source.disconnectTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(source.disconnectLabel, role: .destructive, action: onDisconnect)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(source.disconnectMessage)
        }
        .sheet(isPresented: $pickingCalendar) {
            NavigationStack { calendarPicker }
                .sharpitSheet()
        }
        .presentationDetents([.height(calendarPicker == nil && onReplaceKey == nil ? 250 : 310)])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
    }
}

/// The « + » sheet: every source not yet connected, each one a tap from linked.
struct SourceAddSheet: View {
    let sources: [ManagedSource]
    let onConnect: (ManagedSource) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Tout est connecté"),
                        systemImage: "checkmark.circle",
                        description: Text("Toutes les sources disponibles sont déjà reliées à SharpIt.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(sources) { source in
                                Button { onConnect(source) } label: {
                                    HStack(spacing: SharpitSpacing.sm) {
                                        ProviderLogo(provider: source.logo)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source.name)
                                                .font(SharpitTypography.bodyEmphasis)
                                                .foregroundStyle(SharpitColor.foreground)
                                            Text(source.purpose)
                                                .font(SharpitTypography.meta)
                                                .foregroundStyle(SharpitColor.mutedForeground)
                                        }
                                        Spacer(minLength: SharpitSpacing.xs)
                                        SharpitPill(String(localized: "Connecter"), style: .neutral)
                                    }
                                    .contentShape(.rect)
                                }
                                .accessibilityHint("Connecter \(source.name)")
                            }
                        }
                        .sharpitListRows()
                    }
                    .sharpitGroupedList()
                }
            }
            .navigationTitle("Ajouter une source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .sharpitSheet()
    }
}

/// Garmin linked by a Personal API key the athlete creates on Garmin Connect. The key goes from
/// this field to one request and is gone: SharpIt keeps it encrypted, write-only, and only ever
/// shows its last four characters (web ADR-103).
struct GarminKeySheet: View {
    /// Sends the key; answers the failure to show, or nil once Garmin accepted it.
    let onSubmit: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var failure: String?
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    static let createKeyURL = URL(string: "https://connect.garmin.com/app/settings/personalApiToken")!

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    HStack(spacing: SharpitSpacing.sm) {
                        ProviderLogo(provider: .garmin)
                        Text(ManagedSource.garmin.benefit)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Link(destination: Self.createKeyURL) {
                        Label("Créer ma clé sur Garmin Connect", systemImage: "arrow.up.right.square")
                            .font(SharpitTypography.bodyEmphasis)
                    }
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        SharpitFieldLabel(String(localized: "Clé API Garmin"))
                        SecureField(String(localized: "Colle ta clé ici"), text: $apiKey)
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.foreground)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($isFocused)
                            .onSubmit { send() }
                            .sharpitFieldWell(isActive: isFocused)
                    }
                    if let failure {
                        Text(failure)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("SharpIt vérifie la clé auprès de Garmin, la garde chiffrée et ne l'affiche plus jamais. Tu peux la révoquer à tout moment sur Garmin Connect.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    SharpitPrimaryButton(title: String(localized: "Connecter Garmin"), isBusy: isSending) { send() }
                        .disabled(trimmedKey.isEmpty || isSending)
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.top, SharpitSpacing.md)
            }
            .navigationTitle("Garmin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .sharpitSheet()
    }

    private func send() {
        guard !trimmedKey.isEmpty, !isSending else { return }
        isSending = true
        failure = nil
        Task {
            let refusal = await onSubmit(trimmedKey)
            isSending = false
            if let refusal {
                failure = refusal
            } else {
                apiKey = ""
                dismiss()
            }
        }
    }
}
