import SwiftUI

/// « Rattraper ma semaine »: a session missed in the last days opens « Ajuster le planning » with
/// the miss already said, so the coach proposes the rest of the week in one tap. An old miss is
/// history, not something to catch up on, so it offers nothing.
struct PlanCatchUp: Equatable, Sendable {
    /// Past this, a missed session is left alone.
    static let windowDays = 7

    let label: String
    let date: Date

    /// What the coach is told the athlete asks for.
    func focus(now: Date = .now, calendar: Calendar = .current) -> String {
        "J'ai raté « \(label) » \(dayText(now: now, calendar: calendar)). "
            + "Réorganise la suite de ma semaine sans surcharge, en gardant les séances clés."
    }

    static func offer(for entry: PlanEntry, now: Date = .now, calendar: Calendar = .current) -> PlanCatchUp? {
        let missed: PlanCatchUp? = switch entry {
        case .missed(let session):
            PlanCatchUp(label: session.title ?? session.displayType, date: session.date)
        case .brick(let brick) where brick.isMissed:
            PlanCatchUp(label: "Brick \(brick.chain)", date: brick.date)
        default:
            nil
        }
        guard let missed else { return nil }
        let age = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: missed.date),
            to: calendar.startOfDay(for: now)
        ).day ?? .max
        return (1...windowDays).contains(age) ? missed : nil
    }

    private func dayText(now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) {
            return "hier"
        }
        return "le " + date.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)).lowercased()
    }
}

/// What a missed session's « Rattraper ma semaine » does — set by Plan, read by its rows.
struct PlanCatchUpAction {
    let run: (PlanCatchUp) -> Void
    func callAsFunction(_ catchUp: PlanCatchUp) { run(catchUp) }
}

extension EnvironmentValues {
    @Entry var planCatchUp: PlanCatchUpAction?
}

/// The offer under a missed session: small, in the primary tone, one tap to the coach's proposal.
struct PlanCatchUpButton: View {
    let catchUp: PlanCatchUp
    let action: PlanCatchUpAction

    var body: some View {
        Button {
            action(catchUp)
        } label: {
            Label("Rattraper ma semaine", systemImage: "arrow.triangle.2.circlepath")
                .font(SharpitTypography.meta.weight(.semibold))
                .foregroundStyle(SharpitColor.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SharpitColor.primary.opacity(0.10), in: Capsule())
                .frame(minHeight: SharpitSpacing.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Le coach propose la suite de ta semaine")
    }
}
