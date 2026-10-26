import SwiftUI

/// The whole of a session in time: the mobility before, the session, the stretches after.
///
/// The prescribed duration counts the session alone; the athlete blocks the time of all three,
/// so the drawer says the sum and shows each part's share of it.
struct SessionSequence: Equatable {
    enum Kind: Equatable {
        case before
        case session
        case after

        var label: String {
            switch self {
            case .before: String(localized: "Mobilité")
            case .session: String(localized: "Séance")
            case .after: String(localized: "Étirements")
            }
        }
    }

    struct Part: Equatable, Identifiable {
        let kind: Kind
        let minutes: Int
        var id: Kind { kind }
    }

    let parts: [Part]

    var totalMinutes: Int { parts.reduce(0) { $0 + $1.minutes } }

    /// Nil without routines or without a duration: the session alone is already in its figures.
    static func of(durationMin: Int?, routines: V1SessionRoutines?) -> SessionSequence? {
        guard let durationMin, durationMin > 0, let routines else { return nil }
        let parts = [
            Part(kind: .before, minutes: routines.warmup.minutes),
            Part(kind: .session, minutes: durationMin),
            Part(kind: .after, minutes: routines.cooldown.minutes),
        ].filter { $0.minutes > 0 }
        return SessionSequence(parts: parts)
    }
}

/// « Au total ~57 min » over a bar split in its parts, each named under its own share.
struct SessionSequenceBar: View {
    let sequence: SessionSequence

    /// A two-minute routine beside a ninety-minute ride still needs a visible mark.
    private static let minimumShare: CGFloat = 0.08

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                SharpitEyebrow(String(localized: "Au total"))
                Spacer(minLength: 0)
                Text("~\(sequence.totalMinutes) min")
                    .font(SharpitTypography.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)
            }
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(sequence.parts) { part in
                        Capsule()
                            .fill(part.kind == .session ? SharpitColor.foreground : SharpitColor.track)
                            .frame(width: width(of: part, in: proxy.size.width))
                    }
                }
            }
            .frame(height: 8)
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                ForEach(Array(sequence.parts.enumerated()), id: \.element.id) { index, part in
                    if index > 0 { Spacer(minLength: 0) }
                    Text("\(part.kind.label) \(part.minutes) min")
                        .font(SharpitTypography.meta)
                        .monospacedDigit()
                        .foregroundStyle(part.kind == .session ? SharpitColor.foreground : SharpitColor.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "Au total environ \(sequence.totalMinutes) minutes : ")
                + sequence.parts.map { "\($0.kind.label) \($0.minutes) min" }.joined(separator: ", ")
        )
    }

    private func width(of part: SessionSequence.Part, in total: CGFloat) -> CGFloat {
        let gaps = CGFloat(sequence.parts.count - 1) * 3
        let available = max(total - gaps, 0)
        let shares = sequence.parts.map { max(CGFloat($0.minutes) / CGFloat(sequence.totalMinutes), Self.minimumShare) }
        let share = max(CGFloat(part.minutes) / CGFloat(sequence.totalMinutes), Self.minimumShare)
        return available * share / shares.reduce(0, +)
    }
}
