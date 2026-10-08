import SwiftUI

/// Paramètres › Sources de données › Priorités: per data class, which connected sources feed it
/// and which one is the primary (SHARPIT ADR-054). The primary is the source of truth; the others
/// fill what it lacks. A class only one source can feed shows it, with nothing to choose.
struct SourcePrioritiesView: View {
    @State private var store: SourcePrefsStore

    init(client: any SourcePrefsServing = SharpitClient(), tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: SourcePrefsStore(client: client, tokenProvider: tokenProvider))
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
        .task { await store.load() }
    }

    private var list: some View {
        List {
            ForEach(store.classes) { sourceClass in
                Section {
                    ForEach(sourceClass.providers.filter { store.isConnected($0.id) }) { provider in
                        row(provider, in: sourceClass)
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
            return "\(base) Touche le nom pour choisir la source principale ; le commutateur active ou coupe la source."
        }
        if store.connectedCount(in: sourceClass.id) > 1 {
            return "\(base) Active au moins deux sources pour en choisir une principale."
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
                            Text(isPrimary ? "Principale" : "Choisir comme principale")
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
            .accessibilityHint(choosesPrimary && !isPrimary ? "En fait la source principale" : "")
            .accessibilityLabel(
                choosesPrimary
                    ? "\(provider.name), \(isPrimary ? "principale" : "pas principale")"
                    : provider.name
            )
            Toggle(
                "Utiliser \(provider.name)",
                isOn: Binding(
                    get: { isEnabled },
                    set: { on in Task { await store.setEnabled(provider.id, in: sourceClass.id, on) } }
                )
            )
            .labelsHidden()
            .tint(SharpitColor.primary)
        }
        .padding(.vertical, SharpitSpacing.xxs)
    }
}
