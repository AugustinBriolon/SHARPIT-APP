import SwiftUI

/// Santé's opening, on the sheet: the scores as rings between two hairlines — the biological
/// age, how many markers sit in their norm, the VO₂max. Only the middle ring is a share (N of M
/// markers); the other two are closed, their reading said in a line under the figure.
///
/// Below Pro the age's column is a lock that opens the paywall: the web never computes the age
/// there, so nothing the app holds could reveal it.
struct SanteHero: View {
    enum Mode: Equatable {
        case age(V1BiologicalAge)
        case locked
        case norms

        init(_ synthesis: V1HealthSynthesis) {
            // Locked first: below Pro nothing shows an age, whatever the payload holds.
            if synthesis.biologicalAgeRequiresPro {
                self = .locked
            } else if let age = synthesis.biologicalAge {
                self = .age(age)
            } else {
                self = .norms
            }
        }
    }

    let synthesis: V1HealthSynthesis
    var vo2max: V1HealthMarker? = nil

    @State private var isShowingPaywall = false
    @Environment(ProStore.self) private var pro: ProStore?

    private var mode: Mode { Mode(synthesis) }

    var body: some View {
        CliniqueScoreStrip {
            ageColumn
            if synthesis.normed > 0 {
                CliniqueScoreColumn(
                    pillar: .sleep,
                    fraction: Double(synthesis.inNorm) / Double(synthesis.normed),
                    symbol: "heart",
                    title: String(localized: "Dans la norme"),
                    value: "\(synthesis.inNorm)",
                    scale: "\(synthesis.normed)",
                    note: String(localized: "repères mesurés")
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SanteReadout.synthesis(synthesis) ?? "")
            }
            if let vo2max {
                CliniqueScoreColumn(
                    pillar: .recovery,
                    // A closed ring: a measure, not a share of anything. Its norm says how it reads.
                    fraction: 1,
                    symbol: "bolt",
                    title: "VO₂max",
                    value: SanteReadout.number(vo2max.value, digits: 0),
                    unit: "ml/kg",
                    note: vo2max.norm?.label
                )
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private var ageColumn: some View {
        switch mode {
        case .age(let age):
            CliniqueScoreColumn(
                pillar: .nutrition,
                // A closed ring too: the gap to the civil age is said in words under it.
                fraction: 1,
                symbol: "figure.stand",
                title: String(localized: "Âge biologique"),
                value: String(localized: "\(BiologicalAgeReadout.years(age.years)) ans"),
                note: SanteHeroReadout.ageNote(age)
            )
            .accessibilityElement(children: .combine)
        case .locked:
            let column = CliniqueScoreColumn(
                pillar: .nutrition, fraction: nil, symbol: "lock",
                title: String(localized: "Âge biologique"), value: "Pro"
            )
            if let pro {
                Button { isShowingPaywall = true } label: { column.contentShape(.rect) }
                    .buttonStyle(.sharpitPressable)
                    .sheet(isPresented: $isShowingPaywall) { SharpitProPaywallSheet(store: pro) }
                    .accessibilityLabel("Débloquer avec SharpIt Pro")
                    .accessibilityHint("Ton âge biologique, calculé par SharpIt à partir de ta VO₂max")
            } else {
                column
            }
        case .norms:
            EmptyView()
        }
    }
}

/// How Santé's opening and its tables read a tone: the pill's status and word, the age's ring.
enum SanteHeroReadout {
    /// « Rien à surveiller », or how many points are; nil when nothing could be read against a norm.
    static func headline(normed: Int, watchCount: Int) -> (text: String, status: CliniqueStatus)? {
        guard normed > 0 || watchCount > 0 else { return nil }
        switch watchCount {
        case 0: return (String(localized: "Rien à surveiller"), .good)
        case 1: return (String(localized: "1 point à surveiller"), .watch)
        default: return (String(localized: "\(watchCount) points à surveiller"), .watch)
        }
    }

    static func wash(watchCount: Int) -> CliniqueWash {
        watchCount == 0 ? .good : .watch
    }

    /// A tone the web judged; a neutral one carries no pill.
    static func status(_ tone: V1HealthTone) -> CliniqueStatus? {
        switch tone {
        case .good: .good
        case .watch: .watch
        case .neutral: nil
        }
    }

    static func word(_ status: CliniqueStatus) -> String {
        status == .good ? String(localized: "Bon") : String(localized: "À surveiller")
    }

    /// « 3 ans de moins », « comme ton âge civil »: the gap, short enough for a column.
    static func ageNote(_ age: V1BiologicalAge) -> String? {
        guard let civil = age.chronologicalYears else { return nil }
        switch Int(civil.rounded()) - Int(age.years.rounded()) {
        case 0: return String(localized: "comme ton âge civil")
        case 1: return String(localized: "1 an de moins")
        case -1: return String(localized: "1 an de plus")
        case let years where years > 0: return String(localized: "\(years) ans de moins")
        case let years: return String(localized: "\(-years) ans de plus")
        }
    }
}
