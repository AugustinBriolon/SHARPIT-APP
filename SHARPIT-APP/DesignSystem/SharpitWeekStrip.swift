import SwiftUI
import UIKit

/// Weeks, one page of seven days at a time.
///
/// Snapped, so a drag always lands on a whole week — never between two. It moves the week
/// rather than merely indexing it, which is what a horizontal strip of dates promises.
/// What each day shows and does belongs to the caller.
struct SharpitWeekStrip<DayCell: View>: View {
    @Binding var weekOffset: Int
    let weeks: SharpitWeeks
    @ViewBuilder let dayCell: (Date) -> DayCell

    init(
        weekOffset: Binding<Int>,
        weeks: SharpitWeeks,
        @ViewBuilder dayCell: @escaping (Date) -> DayCell
    ) {
        _weekOffset = weekOffset
        self.weeks = weeks
        self.dayCell = dayCell
        _position = State(initialValue: weekOffset.wrappedValue)
    }

    /// Seeded at creation: set later, in `onAppear`, a lazy stack has not laid out its pages
    /// yet and the strip opens on the neighbouring week.
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

/// What a day carries in the month view — shape as well as colour, as on the strips.
nonisolated enum SharpitCalendarMark: Equatable, Sendable {
    /// Something happened: an activity recorded, a day with data.
    case filled
    /// Something is expected: a session planned.
    case ring
    /// Expected and not done, or read and empty.
    case muted
}

/// A month, to jump to any day a strip holds.
///
/// The system calendar (`UICalendarView`) rather than a hand-drawn grid: it already handles
/// month paging, the French locale and Monday-first weeks — and unlike the graphical
/// `DatePicker`, it can mark a day, so the athlete sees which dates hold something before
/// tapping one.
struct SharpitCalendarSheet: View {
    let title: String
    let weeks: SharpitWeeks
    let range: ClosedRange<Date>
    let marks: [Date: SharpitCalendarMark]
    let legend: [(SharpitCalendarMark, String)]
    let onPick: (Date) -> Void
    let onToday: () -> Void

    @Environment(\.dismiss) private var dismiss
    private let initial: Date

    init(
        title: String,
        initial: Date,
        weeks: SharpitWeeks,
        range: ClosedRange<Date>? = nil,
        marks: [Date: SharpitCalendarMark] = [:],
        legend: [(SharpitCalendarMark, String)] = [],
        onPick: @escaping (Date) -> Void,
        onToday: @escaping () -> Void
    ) {
        self.title = title
        self.weeks = weeks
        self.range = range ?? weeks.selectableDates
        self.marks = marks
        self.legend = legend
        self.onPick = onPick
        self.onToday = onToday
        self.initial = initial
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    SharpitCalendarView(
                        calendar: weeks.calendar,
                        range: range,
                        selected: initial,
                        marks: marks
                    ) { day in
                        SharpitHaptics.play(.light)
                        onPick(day)
                        dismiss()
                    }
                    .accessibilityLabel(title)

                    if !legend.isEmpty {
                        HStack(spacing: SharpitSpacing.md) {
                            ForEach(Array(legend.enumerated()), id: \.offset) { _, entry in
                                HStack(spacing: SharpitSpacing.xxs) {
                                    SharpitCalendarMarkSwatch(mark: entry.0)
                                    Text(entry.1)
                                        .font(SharpitTypography.meta)
                                        .foregroundStyle(SharpitColor.mutedForeground)
                                }
                            }
                        }
                        .padding(.horizontal, SharpitSpacing.xs)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
            }
            .scrollBounceBehavior(.basedOnSize)
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
        }
        .presentationDetents([.fraction(0.66), .large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
    }
}

/// The legend's sample of a mark, drawn the way the calendar draws it.
private struct SharpitCalendarMarkSwatch: View {
    let mark: SharpitCalendarMark

    var body: some View {
        Group {
            switch mark {
            case .filled: Circle().fill(SharpitColor.primary)
            case .ring: Circle().strokeBorder(SharpitColor.primary, lineWidth: 1.25)
            case .muted: Circle().fill(SharpitColor.mutedForeground)
            }
        }
        .frame(width: 7, height: 7)
    }
}

/// `UICalendarView` for SwiftUI: one selectable date, and a decoration under each marked day.
/// Marks can arrive after the sheet opens; only the days whose mark changed are redrawn.
private struct SharpitCalendarView: UIViewRepresentable {
    let calendar: Calendar
    let range: ClosedRange<Date>
    let selected: Date
    let marks: [Date: SharpitCalendarMark]
    let onPick: (Date) -> Void

    private static let components: Set<Calendar.Component> = [.calendar, .era, .year, .month, .day]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.locale = SharpitLocale.french
        view.fontDesign = .default
        view.tintColor = UIColor(SharpitColor.primary)
        view.availableDateRange = DateInterval(start: range.lowerBound, end: range.upperBound)
        view.delegate = context.coordinator

        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.setSelected(calendar.dateComponents(Self.components, from: selected), animated: false)
        view.selectionBehavior = selection
        view.setVisibleDateComponents(calendar.dateComponents(Self.components, from: selected), animated: false)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let previous = context.coordinator.parent.marks
        context.coordinator.parent = self
        let changed = Set(previous.keys).union(marks.keys).filter { previous[$0] != marks[$0] }
        guard !changed.isEmpty else { return }
        view.reloadDecorations(
            forDateComponents: changed.map { calendar.dateComponents(Self.components, from: $0) },
            animated: true
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context _: Context) -> CGSize? {
        let width = proposal.width ?? 360
        let fitted = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fitted.height)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: SharpitCalendarView

        init(_ parent: SharpitCalendarView) {
            self.parent = parent
        }

        func calendarView(_: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let date = parent.calendar.date(from: dateComponents) else { return nil }
            switch parent.marks[parent.calendar.startOfDay(for: date)] {
            case .filled:
                return .default(color: UIColor(SharpitColor.primary), size: .small)
            case .ring:
                return .image(
                    UIImage(systemName: "circle"),
                    color: UIColor(SharpitColor.primary),
                    size: .small
                )
            case .muted:
                return .default(color: UIColor(SharpitColor.mutedForeground), size: .small)
            case nil:
                return nil
            }
        }

        func dateSelection(_: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let date = parent.calendar.date(from: dateComponents) else { return }
            parent.onPick(date)
        }

        func dateSelection(_: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            dateComponents != nil
        }
    }
}

/// The way back to today, for any screen that moves through days or weeks.
///
/// It lives in the navigation bar, where the system draws it in Liquid Glass beside the
/// screen's other controls, and only while the screen is away from today: on today it would
/// be a button that does nothing, and the design law asks for silence over decoration.
struct SharpitTodayButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            SharpitHaptics.play(.light)
            SharpitMotion.run(SharpitMotion.selection, action)
        } label: {
            Text("Aujourd'hui")
                .fixedSize()
        }
        .accessibilityHint("Revient à aujourd'hui")
    }
}
