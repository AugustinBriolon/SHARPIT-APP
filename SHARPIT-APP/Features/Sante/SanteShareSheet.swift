import SwiftUI

/// What Santé can hand out, each a ready-made card: only what the overview really holds.
enum SanteShareCard: Hashable, Identifiable {
    case summary
    case age
    case vo2max

    var id: Self { self }

    var title: String {
        switch self {
        case .summary: String(localized: "Bilan")
        case .age: String(localized: "Âge biologique")
        case .vo2max: "VO₂max"
        }
    }

    /// The cards an overview can fill, in the order they are offered.
    static func available(for overview: V1HealthOverview) -> [SanteShareCard] {
        var cards: [SanteShareCard] = []
        if overview.synthesis.normed > 0 { cards.append(.summary) }
        if case .age = SanteHero.Mode(overview.synthesis) { cards.append(.age) }
        if overview.marker(.vo2max) != nil { cards.append(.vo2max) }
        return cards
    }
}

/// Santé's « Partager »: the cards to choose from, one a page, then the system's share sheet
/// with the chosen one as an image — or the figures as plain text.
struct SanteShareSheet: View {
    let overview: V1HealthOverview

    @State private var selection: SanteShareCard?
    @State private var rendered: Image?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private var cards: [SanteShareCard] { SanteShareCard.available(for: overview) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Partager")
                    .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title))
                    .tracking(-0.4)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text("Choisis une carte, elle part en image.")
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.slate)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.trailing, 56)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(cards) { card in
                        SanteShareCardView(card: card, overview: overview)
                            .frame(width: SanteShareCardView.width)
                            .id(card)
                            .accessibilityElement(children: .combine)
                            // The card not chosen steps back, so the one that leaves is plain.
                            .opacity(card == selection ? 1 : 0.5)
                            .animation(SharpitMotion.selection, value: selection)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 20)
            }
            .contentMargins(.horizontal, 24, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection)
            .scrollIndicators(.hidden)

            HStack(spacing: 6) {
                ForEach(cards) { card in
                    Circle()
                        .fill(card == selection ? SharpitColor.foreground : SharpitColor.divider)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            Spacer(minLength: 16)

            VStack(spacing: 6) {
                if let rendered, let selection {
                    ShareLink(item: rendered, preview: SharePreview(selection.title, image: rendered)) {
                        Text("Partager cette carte").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                }
                ShareLink(item: SanteReadout.shareText(overview)) {
                    Text("Partager en texte")
                }
                .buttonStyle(CliniqueButtonStyle(kind: .plain))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, SharpitSpacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .presentationDragIndicator(.visible)
        .sharpitSheet()
        .onAppear { if selection == nil { selection = cards.first } }
        .task(id: selection) { render() }
    }

    /// The chosen card as the image that leaves: light, at the screen's scale, whatever the
    /// phone's appearance.
    private func render() {
        guard let selection else { return }
        let renderer = ImageRenderer(
            content: SanteShareCardView(card: selection, overview: overview)
                .frame(width: SanteShareCardView.width)
        )
        renderer.scale = displayScale
        rendered = renderer.uiImage.map(Image.init(uiImage:))
    }
}

/// One card, made to leave the app: ink like the brand's mark, one ring, one figure, the words
/// that give it its meaning — a poster, not a screenshot. Colours are fixed (ink, white, the
/// pillar's hue) so the image reads the same whatever the phone's appearance.
struct SanteShareCardView: View {
    static let width: CGFloat = 300

    let card: SanteShareCard
    let overview: V1HealthOverview

    private static let ink = Color(red: 0.055, green: 0.055, blue: 0.055)
    private static let quiet = Color.white.opacity(0.62)
    private static let rule = Color.white.opacity(0.14)

    var body: some View {
        let reading = SanteShareReadout.reading(card, overview)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagonpath.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(SharpitColor.brandMarkGradient)
                Text(verbatim: "SharpIt")
                    .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(Date.now.sharpitFormatted(.dateTime.day().month(.abbreviated).year()))
                    .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(Self.quiet)
            }

            ZStack {
                Circle().stroke(Self.rule, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CliniqueRingMath.trim(for: reading.fraction))
                    .stroke(hue, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(reading.value)
                        .font(SharpitTypography.system(size: 54, weight: .semibold, relativeTo: .largeTitle, digits: true))
                        .tracking(-2)
                        .foregroundStyle(.white)
                    Text(reading.unit)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(Self.quiet)
                }
            }
            .frame(width: 150, height: 150)
            .frame(maxWidth: .infinity)
            .padding(.top, 26)

            Spacer(minLength: 18)

            Text(reading.title)
                .font(SharpitTypography.system(size: 22, weight: .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .foregroundStyle(.white)
            if let note = reading.note {
                Text(note)
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(Self.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
            if !reading.facts.isEmpty {
                Rectangle().fill(Self.rule).frame(height: 1).padding(.top, 14)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(reading.facts.enumerated()), id: \.offset) { _, fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.value)
                                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline, digits: true))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(fact.name)
                                .font(SharpitTypography.system(size: 11, weight: .regular, relativeTo: .caption2))
                                .foregroundStyle(Self.quiet)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(22)
        .frame(height: 390, alignment: .topLeading)
        .background(Self.ink)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var hue: Color {
        switch card {
        case .summary: SharpitColor.pillarSleep
        case .age: SharpitColor.pillarNutrition
        case .vo2max: SharpitColor.pillarRecovery
        }
    }
}

/// What a card says, from what the overview holds — nothing else.
enum SanteShareReadout {
    struct Reading {
        let value: String
        let unit: String
        /// The ring's share; a closed ring for a measure that is no part of anything.
        let fraction: Double
        let title: String
        let note: String?
        var facts: [(name: String, value: String)] = []
    }

    static func reading(_ card: SanteShareCard, _ overview: V1HealthOverview) -> Reading {
        switch card {
        case .summary:
            let synthesis = overview.synthesis
            return Reading(
                value: "\(synthesis.inNorm)", unit: String(localized: "sur \(synthesis.normed)"),
                fraction: synthesis.normed > 0 ? Double(synthesis.inNorm) / Double(synthesis.normed) : 0,
                title: String(localized: "Repères dans la norme"),
                note: nil,
                facts: facts(overview)
            )
        case .age:
            let age = overview.synthesis.biologicalAge
            return Reading(
                value: age.map { BiologicalAgeReadout.years($0.years) } ?? "—", unit: String(localized: "ans"),
                fraction: 1,
                title: String(localized: "Âge biologique"),
                note: age.flatMap(SanteHeroReadout.ageNote)
            )
        case .vo2max:
            let marker = overview.marker(.vo2max)
            return Reading(
                value: marker.map { SanteReadout.number($0.value, digits: 0) } ?? "—", unit: "ml/kg/min",
                fraction: 1,
                title: "VO₂max",
                note: marker?.norm?.label
            )
        }
    }

    /// Up to three vital signs under the summary: resting heart rate, HRV, VO₂max — those measured.
    static func facts(_ overview: V1HealthOverview) -> [(name: String, value: String)] {
        [V1HealthMarker.Key.restingHr, .hrv, .vo2max].compactMap { key in
            overview.marker(key).map { marker in
                let value = SanteReadout.value(marker)
                return (SanteReadout.title(key), [value.text, value.unit].compactMap { $0 }.joined(separator: " "))
            }
        }
    }
}
