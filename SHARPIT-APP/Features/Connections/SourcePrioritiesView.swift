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
        guard store.offersPrimary(in: sourceClass.id) else { return sourceClass.description }
        return "\(sourceClass.description) La source principale fait foi ; les autres complètent ce qui lui manque."
    }

    private func row(_ provider: V1SourceClass.Provider, in sourceClass: V1SourceClass) -> some View {
        let isEnabled = store.isEnabled(provider.id, in: sourceClass.id)
        let isPrimary = store.isPrimary(provider.id, in: sourceClass.id)
        let choosesPrimary = store.offersPrimary(in: sourceClass.id) && isEnabled
        return HStack(spacing: SharpitSpacing.sm) {
            if let logo = ProviderLogo.Provider(integrationId: provider.id) {
                ProviderLogo(provider: logo)
            }
            Button {
                guard choosesPrimary else { return }
                SharpitHaptics.play(.soft)
                Task { await store.setPrimary(provider.id, in: sourceClass.id) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    if choosesPrimary {
                        Label(isPrimary ? "Principale" : "Choisir comme principale", systemImage: isPrimary ? "checkmark.circle.fill" : "circle")
                            .font(SharpitTypography.meta.weight(isPrimary ? .semibold : .regular))
                            .foregroundStyle(isPrimary ? SharpitColor.primary : SharpitColor.mutedForeground)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!choosesPrimary)
            .accessibilityAddTraits(isPrimary ? [.isSelected] : [])
            .accessibilityHint(choosesPrimary && !isPrimary ? "En fait la source principale" : "")
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
