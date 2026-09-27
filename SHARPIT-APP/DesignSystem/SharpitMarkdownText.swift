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
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    // A heading opens a new part of the answer: it takes air above, not below.
                    .padding(.top, index > 0 && block.isHeading ? SharpitSpacing.xs : 0)
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
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .bulleted(let items):
            list(items) { _ in
                Circle()
                    .fill(SharpitColor.primary)
                    .frame(width: 5, height: 5)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
            }

        case .table(let header, let rows):
            SharpitMarkdownTable(header: header, rows: rows)

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
                        .lineSpacing(3)
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

private extension SharpitMarkdownBlock {
    var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }
}

/// A coach's table on a panel: the header as labels, one row per line, the first column read as
/// the row's name. Wider than the screen, it scrolls sideways rather than squeezing its figures.
private struct SharpitMarkdownTable: View {
    let header: [String]
    let rows: [[String]]

    private var columns: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    var body: some View {
        // Laid flat when it fits; scrolls sideways only when it does not.
        ViewThatFits(in: .horizontal) {
            grid
            ScrollView(.horizontal, showsIndicators: false) { grid }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private var grid: some View {
            Grid(alignment: .leading, horizontalSpacing: SharpitSpacing.md, verticalSpacing: SharpitSpacing.xs) {
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(cell(header, column))
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider().overlay(SharpitColor.analysisGrid).gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            Text(SharpitMarkdown.inline(cell(row, column)))
                                .font(column == 0 ? SharpitTypography.bodyEmphasis : SharpitTypography.body)
                                .monospacedDigit()
                                .foregroundStyle(SharpitColor.foreground)
                                .fixedSize()
                        }
                    }
                }
            }
            .padding(SharpitSpacing.md)
    }

    private func cell(_ row: [String], _ column: Int) -> String {
        column < row.count ? row[column] : ""
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
