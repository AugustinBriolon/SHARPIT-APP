import Foundation
import Testing
@testable import Sharpit

// The coach writes markdown. `AttributedString(markdown:)` handles emphasis but collapses
// block syntax, so blocks are parsed here — and a streaming answer is malformed most of
// the time, which the parser has to survive rather than reject.

@Test func paragraphsSeparatedByBlankLinesStayApart() {
    let blocks = SharpitMarkdown.blocks(from: "Premier point.\n\nSecond point.")

    #expect(blocks == [.paragraph("Premier point."), .paragraph("Second point.")])
}

@Test func aWrappedParagraphIsJoinedBackIntoOne() {
    // Soft wraps in the source are not line breaks in the prose.
    let blocks = SharpitMarkdown.blocks(from: "Tu peux\ny aller.")

    #expect(blocks == [.paragraph("Tu peux y aller.")])
}

@Test func headingsCarryTheirLevel() {
    let blocks = SharpitMarkdown.blocks(from: "# Un\n## Deux\n### Trois")

    #expect(
        blocks == [
            .heading(level: 1, text: "Un"),
            .heading(level: 2, text: "Deux"),
            .heading(level: 3, text: "Trois"),
        ]
    )
}

@Test func deepHeadingsClampRatherThanDisappear() {
    #expect(SharpitMarkdown.blocks(from: "##### Profond") == [.heading(level: 3, text: "Profond")])
}

@Test func aHashWithoutTextIsNotAHeading() {
    #expect(SharpitMarkdown.blocks(from: "#") == [.paragraph("#")])
}

@Test func bulletsGatherIntoOneList() {
    let blocks = SharpitMarkdown.blocks(from: "- Mardi\n- Jeudi\n* Dimanche")

    #expect(blocks == [.bulleted(["Mardi", "Jeudi", "Dimanche"])])
}

@Test func numberedItemsGatherIntoOneList() {
    let blocks = SharpitMarkdown.blocks(from: "1. Échauffement\n2. Bloc\n3) Retour au calme")

    #expect(blocks == [.numbered(["Échauffement", "Bloc", "Retour au calme"])])
}

@Test func switchingListStyleStartsANewList() {
    let blocks = SharpitMarkdown.blocks(from: "- Un\n1. Deux")

    #expect(blocks == [.bulleted(["Un"]), .numbered(["Deux"])])
}

@Test func aListInterruptsTheParagraphBeforeIt() {
    let blocks = SharpitMarkdown.blocks(from: "Cette semaine :\n- Mardi")

    #expect(blocks == [.paragraph("Cette semaine :"), .bulleted(["Mardi"])])
}

@Test func aNumberInProseIsNotAListItem() {
    #expect(SharpitMarkdown.blocks(from: "2026 fut une année.") == [.paragraph("2026 fut une année.")])
}

@Test func quotesAndRulesAreTheirOwnBlocks() {
    let blocks = SharpitMarkdown.blocks(from: "> Garde la sortie longue.\n\n---")

    #expect(blocks == [.quote("Garde la sortie longue."), .rule])
}

@Test func aFencedBlockKeepsItsLinesVerbatim() {
    let blocks = SharpitMarkdown.blocks(from: "```\nligne 1\n  ligne 2\n```")

    #expect(blocks == [.code("ligne 1\n  ligne 2")])
}

@Test func markersInsideAFenceAreNotParsed() {
    let blocks = SharpitMarkdown.blocks(from: "```\n- pas une puce\n# pas un titre\n```")

    #expect(blocks == [.code("- pas une puce\n# pas un titre")])
}

@Test func anUnclosedFenceStillYieldsItsBlock() {
    // Mid-stream the closing fence has not arrived; the code must still be readable.
    let blocks = SharpitMarkdown.blocks(from: "```\nen cours")

    #expect(blocks == [.code("en cours")])
}

@Test func emptyTextProducesNoBlocks() {
    #expect(SharpitMarkdown.blocks(from: "").isEmpty)
    #expect(SharpitMarkdown.blocks(from: "\n\n  \n").isEmpty)
}

@Test func nothingIsDroppedFromAMixedAnswer() {
    let blocks = SharpitMarkdown.blocks(
        from: """
        ## Ta semaine

        Trois séances devant toi.

        - Mardi : seuil
        - Jeudi : récup

        > Garde la sortie longue.
        """
    )

    #expect(
        blocks == [
            .heading(level: 2, text: "Ta semaine"),
            .paragraph("Trois séances devant toi."),
            .bulleted(["Mardi : seuil", "Jeudi : récup"]),
            .quote("Garde la sortie longue."),
        ]
    )
}

// MARK: - Inline

@Test func inlineEmphasisIsResolved() {
    let attributed = SharpitMarkdown.inline("Tu as **trois séances**.")

    // The markers are consumed rather than printed.
    #expect(String(attributed.characters) == "Tu as trois séances.")
}

@Test func halfWrittenEmphasisFallsBackToTheRawText() {
    // A stream stops mid-token constantly; blanking the line would be worse than showing
    // the asterisks for one frame.
    let attributed = SharpitMarkdown.inline("Tu as **trois")

    #expect(String(attributed.characters) == "Tu as **trois")
}

@Test func leadingWhitespaceInsideALineSurvives() {
    #expect(String(SharpitMarkdown.inline("  décalé").characters) == "  décalé")
}
