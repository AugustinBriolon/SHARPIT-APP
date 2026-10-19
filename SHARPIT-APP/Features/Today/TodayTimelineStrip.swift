import SwiftUI

/// Chronological day events from `GET /api/v1/today` timeline.
/// Callers: TodayFoldView in TodayView.swift. API: V1TodayResponse.timeline.
/// User: "fix all" — go-all P2 day timeline.
struct TodayTimelineStrip: View {
    let events: [V1DayTimelineEvent]
    /// Grows with the text: a fixed 42 pt broke « 23:59 » a character per line at the largest sizes.
    @ScaledMetric(relativeTo: .footnote) private var clockWidth: CGFloat = 42

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                SharpitCardHeader(title: String(localized: "Fil de la journée"), symbol: "clock", showsChevron: false)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        row(event, isLast: index == events.count - 1)
                    }
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
    }

    private func clock(_ minuteOfDay: Double?) -> String {
        guard let minuteOfDay else { return "—" }
        let total = Int(minuteOfDay.rounded())
        let hour = ((total % (24 * 60)) + 24 * 60) % (24 * 60) / 60
        let minute = ((total % (24 * 60)) + 24 * 60) % (24 * 60) % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    /// One beat of the day: its time, a dot on the rail, what happened. No icon per row — the
    /// rail carries the order, the words carry the kind; a session's dot is lime.
    private func row(_ event: V1DayTimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            Text(event.minuteOfDay == nil ? "" : clock(event.minuteOfDay))
                .font(SharpitTypography.system(size: 13, weight: .semibold, relativeTo: .footnote, digits: true))
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(width: clockWidth, alignment: .leading)
                .padding(.top, 2)

            VStack(spacing: 0) {
                Circle()
                    .fill(event.kind == "session" ? SharpitColor.highlight : SharpitColor.foreground)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                Rectangle()
                    .fill(isLast ? Color.clear : SharpitColor.track)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 4)
            }
            .frame(width: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.foreground)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .padding(.bottom, isLast ? 0 : SharpitSpacing.md)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
