#if DEBUG
import SwiftUI

/// The Clinique primitives on one screen, to compare with the design canvas in the simulator
/// without an account. Debug builds only: `-SharpitCliniqueGallery YES`.
enum CliniqueGalleryDemo {
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "SharpitCliniqueGallery")
    }
}

struct CliniqueGalleryHost: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                hero
                rings
                section("Séance du jour") { proposal }
                section("Statuts") { statuses }
                section("Biomarqueurs") { table }
                section("Boutons") { buttons }
            }
            .padding(.bottom, 96)
        }
        .cliniqueSheet(wash: .watch)
        .overlay(alignment: .bottom) { glassBar }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            CliniqueStatusPill("À ajuster", status: .watch)
            Text("Journée jouable, séance à alléger")
                .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2))
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.center)
            Text("Nuit courte, VFC 8 % sous ta moyenne. Garde le seuil, enlève une répétition.")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SharpitSpacing.lg)
        .padding(.top, SharpitSpacing.lg)
    }

    private var rings: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            HStack(alignment: .top, spacing: 0) {
                score(.sleep, 0.64, "Sommeil", "64", "100")
                score(.recovery, 0.71, "Récup.", "71", "100")
                score(.nutrition, nil, "Nutrition", nil, nil)
                score(.coach, 5.0 / 6.0, "Régularité", "5", "6")
            }
            .padding(.vertical, 18)
            CliniqueDivider()
        }
    }

    private func score(_ pillar: CliniquePillar, _ fraction: Double?, _ label: String, _ value: String?, _ scale: String?) -> some View {
        VStack(spacing: 8) {
            CliniqueRing(pillar: pillar, fraction: fraction)
            Text(label)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
            if let value, let scale {
                (Text(value).font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true)).foregroundStyle(SharpitColor.foreground)
                    + Text(" / \(scale)").font(SharpitTypography.meta).foregroundStyle(SharpitColor.slate))
            } else {
                Text("Pas encore")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .foregroundStyle(SharpitColor.foreground)
            content()
        }
        .padding(.horizontal, SharpitSpacing.lg)
    }

    private var proposal: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Proposition du matin")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                Text("2 × 12 min au lieu de 3")
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                Text("Même intensité, 12 minutes de moins au seuil.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            HStack(spacing: SharpitSpacing.md) {
                Button("Alléger") {}.buttonStyle(.cliniquePrimary)
                Button("Garder le plan") {}.buttonStyle(.cliniquePlain)
            }
        }
        .cliniqueCard()
    }

    private var statuses: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CliniqueStatusPill("Bon", status: .good)
                CliniqueStatusPill("À surveiller", status: .watch)
                CliniqueStatusPill("Attention", status: .alert)
            }
            HStack(spacing: 8) {
                CliniqueStatusPill("À vérifier", status: .unknown)
                CliniqueStatusPill("À protéger", status: .protect)
                CliniqueStatusPill("Pro", status: .pro)
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            marker("Vitamine D", "18 ng/mL", "Attention", .alert)
            CliniqueDivider()
            marker("Ferritine", "28 µg/L", "À surveiller", .watch)
            CliniqueDivider()
            marker("Hémoglobine", "14,8 g/dL", "Bon", .good)
        }
    }

    private func marker(_ name: String, _ value: String, _ word: String, _ status: CliniqueStatus) -> some View {
        HStack {
            Text(name)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
            Spacer()
            CliniqueStatusPill(word, status: status)
            Text(value)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 92, alignment: .trailing)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Alléger") {}.buttonStyle(.cliniquePrimary)
                Button("Passer") {}.buttonStyle(.cliniqueOutline)
                Button("Plus tard") {}.buttonStyle(.cliniquePlain)
            }
            Button("Appliquer") {}.buttonStyle(.cliniquePrimary).disabled(true)
        }
    }

    /// System glass over the scrolled sheet: what the CSS mock-ups could only imitate.
    private var glassBar: some View {
        SharpitGlassGroup {
            HStack(spacing: SharpitSpacing.xs) {
                Button {} label: {
                    Text("Série terminée")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.cliniquePrimaryLarge)
                Button("Ça fait mal") {}
                    .buttonStyle(CliniqueButtonStyle(kind: .outline, isLarge: true))
            }
            .padding(SharpitSpacing.xs)
            .sharpitGlassCapsule()
        }
        .padding(.horizontal, SharpitSpacing.md)
        .padding(.bottom, SharpitSpacing.xs)
    }
}
#endif
