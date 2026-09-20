import SwiftUI

/// Prose written in markdown, rendered on the design system's ramp.
///
/// The coach answers in paragraphs, lists and the occasional heading. Each block takes the
/// type tier it deserves rather than a markdown library's defaults, so an answer sits on
/// the same ramp as the rest of the app.
struct SharpitMarkdownText: View {
    let markdown: String

    private var blocks: [SharpitMarkdownBlock] {
        SharpitMarkdown.blocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            ForEach(blocks) { block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element for VoiceOver: an answer is read as prose, not as a stack of
        // unrelated fragments.
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func view(for block: SharpitMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(SharpitMarkdown.inline(text))
                .font(headingFont(level))
                .tracking(headingTracking(level))
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Text(SharpitMarkdown.inline(text))
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

        case .bulleted(let items):
            list(items) { _ in
                Text("•")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.primary)
            }

        case .numbered(let items):
            list(items) { index in
                Text("\(index + 1).")
                    .font(SharpitTypography.instrument)
                    .foregroundStyle(SharpitColor.primary)
            }

        case .quote(let text):
            Text(SharpitMarkdown.inline(text))
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, SharpitSpacing.sm)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(SharpitColor.primary)
                        .frame(width: 2)
                }

        case .code(let text):
            Text(text)
                .font(SharpitTypography.instrument)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.sm)
                .background(
                    SharpitColor.analysisSurfaceAlt,
                    in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                )
                .textSelection(.enabled)

        case .rule:
            Rectangle()
                .fill(SharpitColor.analysisBorder)
                .frame(height: 1)
        }
    }

    private func list(
        _ items: [String],
        @ViewBuilder marker: @escaping (Int) -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                    marker(index)
                        .frame(minWidth: 16, alignment: .leading)
                    Text(SharpitMarkdown.inline(item))
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: SharpitTypography.sectionTitle
        case 2: SharpitTypography.cardTitle
        default: SharpitTypography.bodyEmphasis
        }
    }

    private func headingTracking(_ level: Int) -> CGFloat {
        switch level {
        case 1: SharpitTypography.sectionTitleTracking
        case 2: SharpitTypography.cardTitleTracking
        default: 0
        }
    }
}

#Preview {
    ScrollView {
        SharpitMarkdownText(
            markdown: """
            ## Ta semaine

            Tu as **trois séances** encore devant toi. La clé est la sortie longue \
            de dimanche.

            - Mardi : seuil, `4:05/km`
            - Jeudi : récupération
            - Dimanche : 2 h en endurance

            > Garde la sortie longue même si le seuil passe mal.
            """
        )
        .padding()
    }
    .background(SharpitCanvasBackground())
}
