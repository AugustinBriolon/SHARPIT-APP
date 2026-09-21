import SwiftUI

/// Weeks, one page of seven days at a time.
///
/// Snapped, so a drag always lands on a whole week — never between two. It moves the week
/// rather than merely indexing it, which is what a horizontal strip of dates promises.
/// What each day shows and does belongs to the caller.
struct SharpitWeekStrip<DayCell: View>: View {
    @Binding var weekOffset: Int
    let weeks: SharpitWeeks
    @ViewBuilder let dayCell: (Date) -> DayCell

    @State private var position: Int?
    /// A horizontal `ScrollView` has no intrinsic height and would otherwise swallow the
    /// screen. Scaled so the row still follows Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 64

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(weeks.offsets, id: \.self) { offset in
                    HStack(spacing: 0) {
                        ForEach(weeks.weekDays(forOffset: offset), id: \.self) { day in
                            dayCell(day)
                                .frame(maxWidth: .infinity)
                        }
                    }
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
        .onAppear { position = weekOffset }
        // Each side follows the other; the equality checks stop the echo.
        .onChange(of: position) { _, new in
            guard let new, new != weekOffset else { return }
            weekOffset = new
        }
        .onChange(of: weekOffset) { _, new in
            guard new != position else { return }
            withAnimation(SharpitMotion.reveal) { position = new }
        }
    }
}

/// One day of the strip: weekday letter, the date in a circle, and a slot for a mark.
struct SharpitStripDay<Mark: View>: View {
    enum Emphasis {
        /// Filled ink circle — the day the screen is about.
        case filled
        /// Primary-colored figure — today, when it is not the filled one.
        case accent
        case plain
        /// A day that cannot be picked.
        case unavailable
    }

    let day: Date
    let emphasis: Emphasis
    @ViewBuilder let mark: Mark

    var body: some View {
        VStack(spacing: SharpitSpacing.xxs) {
            Text(day.sharpitFormatted(.dateTime.weekday(.narrow)))
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .foregroundStyle(SharpitColor.mutedForeground)

            Text(day.sharpitFormatted(.dateTime.day()))
                .font(SharpitTypography.instrument)
                .foregroundStyle(figureColor)
                .frame(width: 34, height: 34)
                .background(emphasis == .filled ? SharpitColor.inkSurface : Color.clear, in: Circle())
                .animation(SharpitMotion.selection, value: emphasis == .filled)

            mark
                .frame(width: 6, height: 6)
        }
        .contentShape(Rectangle())
        .opacity(emphasis == .unavailable ? 0.35 : 1)
    }

    private var figureColor: Color {
        switch emphasis {
        case .filled: SharpitColor.inkSurfaceForeground
        case .accent: SharpitColor.primary
        case .plain, .unavailable: SharpitColor.foreground
        }
    }
}

extension SharpitStripDay where Mark == Color {
    init(day: Date, emphasis: Emphasis) {
        self.init(day: day, emphasis: emphasis) { Color.clear }
    }
}

/// A month, to jump to any day a strip holds.
///
/// The system graphical picker rather than a hand-drawn grid: it already handles month
/// paging, the French locale and Monday-first weeks.
struct SharpitCalendarSheet: View {
    let title: String
    let weeks: SharpitWeeks
    let range: ClosedRange<Date>
    let onPick: (Date) -> Void
    let onToday: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Date

    init(
        title: String,
        initial: Date,
        weeks: SharpitWeeks,
        range: ClosedRange<Date>? = nil,
        onPick: @escaping (Date) -> Void,
        onToday: @escaping () -> Void
    ) {
        self.title = title
        self.weeks = weeks
        self.range = range ?? weeks.selectableDates
        self.onPick = onPick
        self.onToday = onToday
        _picked = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $picked, in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(SharpitColor.primary)
                .environment(\.locale, SharpitLocale.french)
                .environment(\.calendar, weeks.calendar)
                .padding(.horizontal, SharpitSpacing.pageInset)
                .navigationTitle("Calendrier")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Aujourd'hui") {
                            onToday()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
                .onChange(of: picked) { _, day in
                    onPick(day)
                    dismiss()
                }
        }
        .presentationDetents([.medium])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
    }
}
