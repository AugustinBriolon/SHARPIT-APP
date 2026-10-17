import SwiftUI

/// The sheet a connected source opens: what it brings, how it stands, and the way out. The
/// confirmation lives here so the sheet and the question it asks leave together.
struct SourceManageSheet: View {
    let source: ManagedSource
    let status: ConnectionsReadout.Line
    let onDisconnect: () -> Void

    @State private var confirming = false

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
        .presentationDetents([.height(250)])
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
                        "Tout est connecté",
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
                                        SharpitPill("Connecter", style: .neutral)
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
