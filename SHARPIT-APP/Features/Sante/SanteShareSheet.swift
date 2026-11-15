import SwiftUI

/// What Santé can hand out, each a ready-made card: only what the overview really holds.
enum SanteShareCard: Hashable, Identifiable {
    case summary
    case age
    case vo2max
    case markers

    var id: Self { self }

    var title: String {
        switch self {
        case .summary: String(localized: "Bilan")
        case .age: String(localized: "Âge biologique")
        case .vo2max: "VO₂max"
        case .markers: String(localized: "Repères")
        }
    }

    /// The cards an overview can fill, in the order they are offered.
    static func available(for overview: V1HealthOverview) -> [SanteShareCard] {
        var cards: [SanteShareCard] = []
        if overview.synthesis.normed > 0 { cards.append(.summary) }
        if case .age = SanteHero.Mode(overview.synthesis) { cards.append(.age) }
        if overview.marker(.vo2max) != nil { cards.append(.vo2max) }
        if !overview.allMarkers.isEmpty { cards.append(.markers) }
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
                .environment(\.colorScheme, .light)
        )
        renderer.scale = displayScale
        rendered = renderer.uiImage.map(Image.init(uiImage:))
    }
}

/// One card: the brand and the day on top, the reading in the middle, on the sheet's white under
/// its wash.
struct SanteShareCardView: View {
    static let width: CGFloat = 300

    let card: SanteShareCard
    let overview: V1HealthOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagonpath.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(SharpitColor.brandMarkGradient)
                Text(verbatim: "SharpIt")
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.foreground)
                Spacer(minLength: 0)
                Text(Date.now.sharpitFormatted(.dateTime.day().month(.abbreviated).year()))
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
            Spacer(minLength: 20)
            content
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(height: 330, alignment: .topLeading)
        .background {
            ZStack(alignment: .top) {
                SharpitColor.card
                LinearGradient(colors: [wash.color, SharpitColor.card], startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(SharpitColor.divider, lineWidth: 1))
    }

    private var wash: CliniqueWash {
        switch card {
        case .summary, .markers: .sleep
        case .age: .watch
        case .vo2max: .good
        }
    }

    @ViewBuilder
    private var content: some View {
        switch card {
        case .summary:
            figure(
                eyebrow: String(localized: "Dans la norme"),
                value: "\(overview.synthesis.inNorm)", scale: "/ \(overview.synthesis.normed)",
                note: nil
            )
            if let line = SanteReadout.synthesis(overview.synthesis) {
                Text(line)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        case .age:
            if let age = overview.synthesis.biologicalAge {
                figure(
                    eyebrow: String(localized: "Âge biologique"),
                    value: BiologicalAgeReadout.years(age.years), scale: String(localized: "ans"),
                    note: SanteHeroReadout.ageNote(age)
                )
            }
        case .vo2max:
            if let marker = overview.marker(.vo2max) {
                figure(
                    eyebrow: "VO₂max",
                    value: SanteReadout.number(marker.value, digits: 0), scale: "ml/kg/min",
                    note: marker.norm?.label
                )
            }
        case .markers:
            Text("Mes repères")
                .font(SharpitTypography.system(size: 20, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(SharpitColor.foreground)
                .padding(.bottom, 6)
            ForEach(overview.allMarkers.prefix(6)) { marker in
                let value = SanteReadout.value(marker)
                CliniqueDivider()
                HStack(spacing: 8) {
                    Image(systemName: SanteReadout.symbol(marker.key))
                        .font(.system(size: 13))
                        .foregroundStyle(SharpitColor.slate)
                        .frame(width: 20, alignment: .leading)
                    Text(SanteReadout.title(marker.key))
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text([value.text, value.unit].compactMap { $0 }.joined(separator: " "))
                        .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                }
                .padding(.vertical, 9)
            }
        }
    }

    private func figure(eyebrow: String, value: String, scale: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(SharpitTypography.system(size: 72, weight: .semibold, relativeTo: .largeTitle, digits: true))
                    .tracking(-2.5)
                    .foregroundStyle(SharpitColor.foreground)
                Text(scale)
                    .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
            if let note {
                Text(note)
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.foreground)
            }
        }
    }
}
