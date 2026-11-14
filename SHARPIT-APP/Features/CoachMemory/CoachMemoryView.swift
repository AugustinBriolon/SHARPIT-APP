import SwiftUI

/// Coach → Mémoire, on its mock-up (`docs/adr/0035`): what lasts about the athlete, in their
/// words and as injuries, preferences and notes — each a line that can be corrected or erased.
/// Dated trips and constraints shape the calendar, so they live in Plan (`PlanTripsView`).
struct CoachMemoryView: View {
    @State private var store: CoachMemoryStore
    @State private var route: CoachMemoryFormRoute?
    /// Nil shows every kind.
    @State private var filter: CoachMemoryType?

    private static let kinds: [CoachMemoryType] = [.injury, .preference, .note]

    init(client: any CoachMemoryServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: CoachMemoryStore(client: client, tokenProvider: tokenProvider))
    }

    private var entries: [CoachMemoryEntry] { store.entries.filter { Self.kinds.contains($0.type) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mémoire du coach")
                        .font(SharpitTypography.system(size: 32, weight: .semibold, relativeTo: .largeTitle))
                        .tracking(-0.6)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(CoachMemoryReadout.lead(entries.count))
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !entries.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            chip(String(localized: "Tout"), count: entries.count, kind: nil)
                            ForEach(Self.kinds) { kind in
                                let count = entries.filter { $0.type == kind }.count
                                if count > 0 { chip(kind.shortLabel, count: count, kind: kind) }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
                let shown = entries.filter { filter == nil || $0.type == filter }
                VStack(spacing: 0) {
                    ForEach(shown) { entry in
                        if entry.id != shown.first?.id { CliniqueDivider() }
                        row(entry)
                    }
                }
                context
            }
            .padding(.horizontal, 24)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .cliniqueSheet(wash: .coach, height: 240)
        .navigationTitle("Mémoire du coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Text("") } }
        .overlay(alignment: .bottomTrailing) {
            Button { route = .new } label: { Text("Dire quelque chose au coach") }
                .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                .padding(.trailing, 16)
                .padding(.bottom, 4)
        }
        .navigationDestination(item: $route) { route in
            CoachMemoryEntryForm(store: store, kinds: Self.kinds, entry: route.entry)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private func chip(_ title: String, count: Int, kind: CoachMemoryType?) -> some View {
        let isOn = filter == kind
        return Button { withAnimation(SharpitMotion.selection) { filter = kind } } label: {
            Text("\(title) · \(count)")
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline, digits: true))
                .foregroundStyle(isOn ? SharpitColor.primaryForeground : SharpitColor.foreground)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(isOn ? SharpitColor.primary : SharpitColor.card, in: Capsule())
                .overlay(Capsule().strokeBorder(SharpitColor.divider, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// One thing kept: what it says, its kind and when it was kept, and the cross that erases it.
    private func row(_ entry: CoachMemoryEntry) -> some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Button { route = .edit(entry) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    if entry.trainingConstraint != .full {
                        CliniqueStatusPill(String(localized: "Pèse sur le plan"), status: .watch)
                    }
                    Text(CoachMemoryReadout.text(entry))
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CoachMemoryReadout.kept(entry))
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityHint("Ouvre pour corriger")
            Button { Task { await store.deleteEntry(id: entry.id) } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.slate)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityLabel("Effacer")
        }
        .padding(.vertical, 12)
    }

    /// The athlete's own words about themselves, which the coach reads before anything else.
    private var context: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ce que le coach sait de toi")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                TextEditor(text: $store.profileContextText)
                    .frame(minHeight: 120)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .scrollContentBackground(.hidden)
                HStack {
                    Text("\(store.profileContextText.count) / 4 000")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .monospacedDigit()
                    Spacer()
                    if store.isContextDirty {
                        Button("Enregistrer") { Task { await store.saveContext() } }
                            .buttonStyle(CliniqueButtonStyle(kind: .outline))
                    }
                }
            }
            .cliniqueCard()
        }
        .padding(.top, 6)
    }
}

/// How the coach's memory words an entry.
nonisolated enum CoachMemoryReadout {
    /// « 14 choses retenues de vos échanges. Tu peux tout corriger ou effacer. »
    static func lead(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Rien de retenu pour l'instant. Dis au coach ce qui compte : il s'en souviendra.")
        case 1: String(localized: "1 chose retenue de vos échanges. Tu peux la corriger ou l'effacer.")
        default: String(localized: "\(count) choses retenues de vos échanges. Tu peux tout corriger ou effacer.")
        }
    }

    /// The note when there is one — it is the athlete's sentence — else the entry's name.
    static func text(_ entry: CoachMemoryEntry) -> String {
        guard let note = entry.note, !note.isEmpty else { return entry.displayTitle }
        guard let label = entry.label, !label.isEmpty, label != note else { return note }
        return "\(label) : \(note)"
    }

    /// « Blessure · retenu le 18 mars ».
    @MainActor static func kept(_ entry: CoachMemoryEntry, locale: Locale = SharpitLocale.current) -> String {
        let day = entry.startDate.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        return String(localized: "\(entry.type.shortLabel) · retenu le \(day)")
    }
}
