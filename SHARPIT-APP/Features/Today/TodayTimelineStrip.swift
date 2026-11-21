import SwiftUI

/// Chronological day events from `GET /api/v1/today` timeline.
/// Callers: TodayFoldView in TodayView.swift. API: V1TodayResponse.timeline.
/// User: "fix all" — go-all P2 day timeline.
struct TodayTimelineStrip: View {
    let events: [V1DayTimelineEvent]

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                Text("Fil de la journée")
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        row(event, isFirst: index == 0, isLast: index == events.count - 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func clock(_ minuteOfDay: Double?) -> String {
        guard let minuteOfDay else { return "—" }
        let total = Int(minuteOfDay.rounded())
        let hour = ((total % (24 * 60)) + 24 * 60) % (24 * 60) / 60
        let minute = ((total % (24 * 60)) + 24 * 60) % (24 * 60) % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    /// One beat of the day down the rail, as Plan's week reads: a dot, the time above what
    /// happened. A session done fills its dot with the good status mark; a planned one, and the
    /// rest, stay hollow — a green dot before the session read as already done.
    private func row(_ event: V1DayTimelineEvent, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : SharpitColor.outline).frame(width: 1, height: 16)
                Group {
                    if event.isDoneSession {
                        Circle().fill(SharpitColor.statusGoodMark)
                    } else {
                        Circle().strokeBorder(SharpitColor.slate, lineWidth: 1.5)
                    }
                }
                .frame(width: 12, height: 12)
                Rectangle().fill(isLast ? Color.clear : SharpitColor.outline).frame(width: 1).frame(maxHeight: .infinity)
            }
            .frame(width: 12)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text([event.minuteOfDay == nil ? nil : clock(event.minuteOfDay), event.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                    Text(event.title)
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !isLast { CliniqueDivider() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
