import SwiftUI

/// The week's title. Tapping it opens the calendar — the way to reach a week that is not
/// next door, which a swipe would take a dozen gestures to get to.
struct PlanWeekHeader: View {
    let store: PlanStore
    let onOpenCalendar: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Button(action: onOpenCalendar) {
                HStack(spacing: SharpitSpacing.xxs) {
                    Text(weekRange)
                        .font(SharpitTypography.verdict)
                        .tracking(SharpitTypography.verdictTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    Image(systemName: "chevron.down")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Semaine du \(weekRange)")
            .accessibilityHint("Ouvre le calendrier")

            Spacer(minLength: 0)

            // Only when it is a way back. On the current week it would be a button that
            // does nothing, and the design law asks for silence over decoration.
            if !store.isCurrentWeek {
                Button("Aujourd'hui") { store.goToToday() }
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.primary)
            }
        }
    }

    private var weekRange: String {
        guard let end = store.weekDays.last else {
            return store.weekStart.sharpitFormatted(.dateTime.day().month(.wide))
        }
        let formatter = DateIntervalFormatter()
        formatter.locale = SharpitLocale.french
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: store.weekStart, to: end)
            .replacingOccurrences(of: " 2026", with: "")
    }
}

/// The weeks, one page of seven days at a time.
///
/// Snapped, so a drag always lands on a whole week — never between two. It moves the week
/// rather than merely indexing it, which is what a horizontal strip of dates promises.
/// Tapping a day inside the visible week scrolls the list to it.
///
/// It shares `selectedOffset` with the content pager, so dragging either moves both.
struct PlanWeekStrip: View {
    let store: PlanStore

    @State private var position: Int?
    /// A horizontal `ScrollView` has no intrinsic height and would otherwise swallow the
    /// screen. Scaled so the row still follows Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 64

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(PlanStore.offsets, id: \.self) { offset in
                    PlanStripWeek(store: store, offset: offset)
                        .containerRelativeFrame(.horizontal)
                        .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position)
        .frame(height: rowHeight)
        .padding(.vertical, SharpitSpacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SharpitColor.analysisBorder)
                .frame(height: 1)
        }
        .onAppear { position = store.selectedOffset }
        // Each side follows the other; the equality checks stop the echo.
        .onChange(of: position) { _, new in
            guard let new, new != store.selectedOffset else { return }
            store.selectedOffset = new
        }
        .onChange(of: store.selectedOffset) { _, new in
            guard new != position else { return }
            withAnimation(SharpitMotion.reveal) { position = new }
        }
    }
}

private struct PlanStripWeek: View {
    let store: PlanStore
    let offset: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(store.weekDays(forOffset: offset), id: \.self) { day in
                Button { store.scrollTarget = day } label: {
                    PlanStripDay(day: day, status: store.status(on: day, offset: offset))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct PlanStripDay: View {
    let day: Date
    let status: PlanDayStatus?

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Text(day.sharpitFormatted(.dateTime.weekday(.narrow)))
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .foregroundStyle(SharpitColor.mutedForeground)

            Text(day.sharpitFormatted(.dateTime.day()))
                .font(SharpitTypography.instrument)
                .foregroundStyle(
                    isToday ? SharpitColor.inkSurfaceForeground : SharpitColor.foreground
                )
                .frame(width: 34, height: 34)
                .background(isToday ? SharpitColor.inkSurface : Color.clear, in: Circle())

            statusDot
                .frame(width: 6, height: 6)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Fait défiler la liste jusqu'à ce jour")
        .accessibilityAddTraits(.isButton)
    }

    /// Three states, distinguished by shape as well as colour: a filled dot, a ring, and a
    /// muted dot. Colour alone would not survive colour-blindness or a bright screen.
    @ViewBuilder
    private var statusDot: some View {
        switch status {
        case .executed:
            Circle().fill(SharpitColor.primary)
        case .planned:
            Circle().strokeBorder(SharpitColor.primary, lineWidth: 1.25)
        case .missed:
            Circle().fill(SharpitColor.mutedForeground)
        case nil:
            Color.clear
        }
    }

    private var accessibilityLabel: String {
        let date = day.sharpitFormatted(.dateTime.weekday(.wide).day())
        switch status {
        case .executed: return "\(date), séance réalisée"
        case .planned: return "\(date), séance prévue"
        case .missed: return "\(date), séance non réalisée"
        case nil: return "\(date), repos"
        }
    }
}

/// A month, to jump to any week the pager holds.
///
/// The system graphical picker rather than a hand-drawn grid: it already handles month
/// paging, the French locale and Monday-first weeks, and the last thing this screen needs
/// is another surface of its own to keep correct.
struct PlanCalendarSheet: View {
    let store: PlanStore

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Date

    init(store: PlanStore) {
        self.store = store
        _picked = State(initialValue: store.weekStart)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = SharpitLocale.french
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        NavigationStack {
            DatePicker(
                "Semaine",
                selection: $picked,
                in: store.selectableDates,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(SharpitColor.primary)
            .environment(\.locale, SharpitLocale.french)
            .environment(\.calendar, calendar)
            .padding(.horizontal, SharpitSpacing.pageInset)
            .navigationTitle("Calendrier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Aujourd'hui") {
                        store.goToToday()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onChange(of: picked) { _, day in
                store.showWeek(containing: day)
                dismiss()
            }
        }
        .presentationDetents([.medium])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
    }
}
