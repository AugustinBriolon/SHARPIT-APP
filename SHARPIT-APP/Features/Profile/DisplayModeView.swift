import SwiftData
import SwiftUI

/// Paramètres → Densité de lecture: how much of the technical layer the athlete wants shown
/// (ADR 0006).
///
/// Saves on the tap, with no form to submit, as the web's Personnalisation picker does. The
/// density lives on the profile rather than on the handset, so choosing expert here is
/// choosing it everywhere.
struct DisplayModeView: View {
    @State private var store: AthleteProfileStore
    let displayMode: DisplayModeStore

    init(
        client: any AthleteProfileServing,
        displayMode: DisplayModeStore,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        _store = State(initialValue: AthleteProfileStore(
            client: client,
            tokenProvider: tokenProvider,
            modelContext: modelContext
        ))
        self.displayMode = displayMode
    }

    var body: some View {
        Group {
            switch store.phase {
            case .unauthorized:
                SharpitStateMessage.sessionExpired()
            case .failed(let message):
                SharpitStateMessage.failed(message) { Task { await store.load() } }
            case .idle, .loading, .loaded:
                list
            }
        }
        .navigationTitle("Densité de lecture")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.phase != .loaded { await store.load() } }
        // Every surface reading the density follows the profile — the tap at once, and a write
        // that failed for good once the profile is read back.
        .onChange(of: store.isExpertReading) { _, isExpert in
            if store.phase == .loaded { displayMode.adopt(isExpert: isExpert) }
        }
    }

    private var list: some View {
        List {
            if store.phase == .loaded {
                Section {
                    DisplayModePicker(isExpert: store.isExpertReading, onSelect: select)
                } footer: {
                    SharpitListFooter(String(localized: "Ce que SharpIt affiche, pas ce qu'il mesure : les deux lectures partent des mêmes calculs. Tu peux changer quand tu veux."))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // Said exactly, screen by screen: a preference that promises more than it changes
                // is worse than none.
                Section(eyebrow: String(localized: "Ce qu'Expert ajoute")) {
                    change(
                        symbol: "waveform.path.ecg",
                        title: String(localized: "Analyse technique dans Activité"),
                        text: String(localized: "NP, IF, VI, EF, découplage, temps par zone, seuils utilisés.")
                    )
                    change(
                        symbol: "chart.xyaxis.line",
                        title: String(localized: "Ta forme dans Plan"),
                        text: String(localized: "CTL, ATL et TSB sur six semaines, TSS des huit dernières.")
                    )
                    change(
                        symbol: "gauge.with.dots.needle.50percent",
                        title: String(localized: "La charge nommée en TSS"),
                        text: String(localized: "« 78 TSS » au lieu de « charge 78 ». Le chiffre est le même.")
                    )
                }
                .sharpitListRows()
            } else {
                Section {
                    DisplayModePicker(isExpert: nil, onSelect: { _ in })
                        .redacted(reason: .placeholder)
                        .accessibilityHidden(true)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .sharpitGroupedList()
    }

    private func change(symbol: String, title: String, text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                Text(text)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            SharpitRowIcon.tile(symbol)
        }
        .padding(.vertical, SharpitSpacing.xxs)
    }

    private func select(_ isExpert: Bool) {
        guard store.isExpertReading != isExpert else { return }
        store.setExpertReading(isExpert)
    }
}


/// The two readings side by side, each shown on the same example session as the screens draw it —
/// the difference seen rather than described, as iOS shows Clair and Sombre. `isExpert` nil is the
/// skeleton, before the profile answers (`docs/adr/0008`).
private struct DisplayModePicker: View {
    let isExpert: Bool?
    let onSelect: (Bool) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: SharpitSpacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: SharpitSpacing.sm))
        layout {
            option(
                expert: false,
                title: String(localized: "Essentiel"),
                audience: String(localized: "En mots plutôt qu'en sigles. Le bon choix pour commencer.")
            )
            option(
                expert: true,
                title: String(localized: "Expert"),
                audience: String(localized: "Zones, charge et seuils, avec les chiffres qui les fondent.")
            )
        }
        .padding(.vertical, SharpitSpacing.sm)
        .animation(SharpitMotion.selection, value: isExpert)
    }

    private func option(expert: Bool, title: String, audience: String) -> some View {
        let isSelected = isExpert == expert
        return Button { onSelect(expert) } label: {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                DisplayModeSample(isExpert: expert)
                    .overlay {
                        RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                            .strokeBorder(SharpitColor.primary, lineWidth: isSelected ? 2 : 0)
                    }
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Text(audience)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    SharpitCheckBox(isOn: isSelected)
                }
                .padding(.horizontal, SharpitSpacing.xxs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(audience)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// One session, read in one density: the label the screens use (`ActivityFormat.trainingLoad`), so
/// the example cannot drift from what Activité and Plan show.
private struct DisplayModeSample: View {
    let isExpert: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitIconTile(symbol: "bicycle")
            VStack(alignment: .leading, spacing: 2) {
                Text("Vélo endurance")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(verbatim: "1 h 30 · \(ActivityFormat.trainingLoad(78, isExpertReading: isExpert))")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
                // The technical layer, on its own line: the essential card keeps the space empty
                // so both cards stand the same height.
                Text(verbatim: "IF 0,81 · TSB −10")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .monospacedDigit()
                    .opacity(isExpert ? 1 : 0)
            }
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityHidden(true)
    }
}
