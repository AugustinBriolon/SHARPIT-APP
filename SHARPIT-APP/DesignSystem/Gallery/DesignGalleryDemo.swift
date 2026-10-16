#if DEBUG
import SwiftUI

/// The Ink & Lime references (ADR-085), rebuilt from the shared components, to compare them
/// with the mock-ups in the simulator without an account. Debug builds only:
/// `-SharpitDesignGallery YES`, or `defaults write app.sharpit.ios SharpitDesignGallery -bool YES`
/// in the simulator when the launcher cannot pass arguments.
enum DesignGalleryDemo {
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "SharpitDesignGallery")
    }
}

struct DesignGalleryHost: View {
    @State private var range = "6M"

    var body: some View {
        ScrollView {
            VStack(spacing: SharpitSpacing.lg) {
                strengthCard
                cardioCard
                sleepCard
                restCard
                progressCard
                setsCard
                summaryCard
            }
            .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
    }

    private var strengthCard: some View {
        GalleryCard {
            SharpitCardHeader(title: "Force", symbol: "dumbbell.fill", subtitle: "Développé couché · cette semaine", showsChevron: false) {
                SharpitPill("NOUVEAU PR", style: .lime)
            }
            SharpitHeroFigure(value: "102,5", unit: "kg", delta: "+5 kg")
            Text("Ton précédent record était 97,5 kg")
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.mutedForeground)
            SharpitProgressBar(label: "Prochain palier", value: "102,5 / 110 kg", fraction: 0.9)
        }
    }

    private var cardioCard: some View {
        GalleryCard {
            SharpitCardHeader(title: "Cardio", symbol: "bolt.fill", subtitle: "5 km le plus rapide · cette semaine", showsChevron: false)
            SharpitHeroFigure(value: "22:14", unit: "minutes")
            SharpitGoalTrack(
                fraction: SharpitProgressMath.fraction(start: 1382, current: 1334, goal: 1260),
                nowLabel: "now",
                nowValue: "22:14",
                startValue: "23:02",
                startLabel: "Record précédent",
                goalValue: "21:00",
                goalLabel: "Prochain objectif"
            )
        }
    }

    private var sleepCard: some View {
        GalleryCard {
            SharpitCardHeader(title: "Score de sommeil", symbol: "moon.fill", subtitle: "Cette nuit · 7 h 32", showsChevron: false)
            ZStack {
                SharpitTickGauge(score: 86, showsScale: true)
                VStack(spacing: SharpitSpacing.xxs) {
                    Text("86")
                        .font(SharpitTypography.system(size: 64, weight: .heavy, relativeTo: .largeTitle, digits: true))
                        .tracking(-2)
                    Text("sur 100")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                    SharpitPill("↑ 8 vs moy.", style: .limeSoft)
                }
                .offset(y: 10)
            }
            .padding(.horizontal, SharpitSpacing.xl)
            Divider().overlay(SharpitColor.border)
            SharpitEyebrow("Ce qui l'a façonné")
            VStack(spacing: SharpitSpacing.md) {
                breakdown("Durée", 94)
                breakdown("Sommeil profond", 91)
                breakdown("Récupération", 88)
                breakdown("Régularité", 72)
            }
        }
    }

    private func breakdown(_ label: String, _ value: Int) -> some View {
        HStack(spacing: SharpitSpacing.md) {
            Text(label)
                .font(SharpitTypography.system(size: 16, weight: .medium, relativeTo: .body))
                .frame(width: 130, alignment: .leading)
            SharpitBarTrack(fraction: Double(value) / 100, tone: SharpitColor.foreground)
                .frame(height: 8)
            Text("\(value)")
                .font(SharpitTypography.system(size: 17, weight: .bold, relativeTo: .body, digits: true))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var restCard: some View {
        GalleryCard {
            VStack(alignment: .leading, spacing: 2) {
                Text("Repos").font(SharpitTypography.cardTitle)
                Text("Développé couché · série 3 sur 4")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            ZStack {
                SharpitScoreRing(fraction: 0.8, lineWidth: 18)
                VStack(spacing: 4) {
                    Text("1:00")
                        .font(SharpitTypography.system(size: 56, weight: .heavy, relativeTo: .largeTitle, digits: true))
                    Text("avant la prochaine série")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .frame(width: 210, height: 210)
            .frame(maxWidth: .infinity)
            HStack(spacing: SharpitSpacing.sm) {
                SharpitPrimaryButton(title: "+15 s", style: .secondary) {}
                SharpitPrimaryButton(title: "Pause", style: .accent, trailingSymbol: "pause.circle.fill") {}
                SharpitPrimaryButton(title: "Passer", trailingSymbol: "forward.circle.fill") {}
            }
        }
    }

    private var progressCard: some View {
        GalleryCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Développé couché").font(SharpitTypography.cardTitle)
                    Text("Progression")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer()
                SharpitSegmentedControl(
                    selection: $range,
                    options: ["6S", "3M", "6M", "1A"].map { .init(value: $0, label: $0) }
                )
                .frame(width: 190)
            }
            SharpitHeroFigure(value: "102,5", unit: "kg")
            Divider().overlay(SharpitColor.border)
            HStack {
                SharpitStatTile(caption: "Meilleure série", value: "102,5×6", isFlat: true)
                SharpitStatTile(caption: "Volume", value: "3 590", unit: "kg", isFlat: true)
                SharpitStatTile(caption: "Séances", value: "14", isFlat: true)
            }
        }
    }

    private var setsCard: some View {
        GalleryCard {
            SharpitCardHeader(title: "Développé couché", symbol: "dumbbell.fill", subtitle: "Barre · Pectoraux", showsChevron: false) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Volume")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                    SharpitRowFigure(value: "3 590", unit: "kg")
                }
            }
            SharpitInsetGroup {
                ForEach(Array([(12, "95"), (10, "100"), (8, "102,5"), (6, "105")].enumerated()), id: \.offset) { index, set in
                    SharpitInsetRow(title: "") {
                        SharpitNumberChip(number: index + 1)
                    } trailing: {
                        HStack(spacing: SharpitSpacing.lg) {
                            SharpitRowFigure(value: "\(set.0)", unit: "×")
                            SharpitRowFigure(value: set.1, unit: "kg")
                            SharpitCheckBox(isOn: true)
                        }
                    }
                }
                SharpitDashedAddButton(title: "Ajouter une série") {}
            }
        }
    }

    private var summaryCard: some View {
        GalleryCard {
            VStack(alignment: .leading, spacing: 2) {
                Text("Push day").font(SharpitTypography.cardTitle)
                Text("Pectoraux · Épaules · Triceps")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            SharpitInsetGroup {
                SharpitInsetRow(title: "Développé couché") {
                    SharpitNumberChip(number: 1)
                } trailing: {
                    SharpitPill("PR", style: .lime)
                    SharpitRowFigure(value: "3 590", unit: "kg")
                }
                SharpitInsetRow(title: "Écarté poulie") {
                    SharpitNumberChip(number: 2)
                } trailing: {
                    SharpitRowFigure(value: "1 460", unit: "kg")
                }
            }
            SharpitProgressBar(label: "Effort", value: "RPE 8,5", fraction: 0.9)
            SharpitPrimaryButton(title: "Enregistrer la séance") {}
        }
    }
}

private struct GalleryCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) { content }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
    }
}
#endif
