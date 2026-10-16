import SwiftUI

/// Chronological day events from `GET /api/v1/today` timeline.
/// Callers: TodayFoldView in TodayView.swift. API: V1TodayResponse.timeline.
/// User: "fix all" — go-all P2 day timeline.
struct TodayTimelineStrip: View {
    let events: [V1DayTimelineEvent]

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                SharpitCardHeader(title: "Fil de la journée", symbol: "clock", showsChevron: false)
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    ForEach(events) { event in
                        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                            Text(clock(event.minuteOfDay))
                                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline, digits: true))
                                .foregroundStyle(SharpitColor.foreground)
                                .frame(width: 48, alignment: .leading)
                            SharpitIconTile(symbol: symbol(for: event.kind), size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                                    .foregroundStyle(SharpitColor.foreground)
                                if let detail = event.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .subheadline))
                                        .foregroundStyle(SharpitColor.mutedForeground)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
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

    private func symbol(for kind: String) -> String {
        switch kind {
        case "sleep": return "moon.zzz"
        case "wake": return "sun.horizon"
        case "session": return "figure.run"
        case "meal": return "fork.knife"
        case "stress": return "waveform.path.ecg"
        case "checkin": return "checkmark.circle"
        case "note": return "note.text"
        default: return "circle"
        }
    }
}
