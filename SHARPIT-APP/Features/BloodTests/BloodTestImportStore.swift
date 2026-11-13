import CoreGraphics
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// One import: read a report on the device, let the athlete correct what was read, send the
/// results. The document is opened, read and let go — never copied or uploaded (SHARPIT ADR-128).
@MainActor
@Observable
final class BloodTestImportStore {
    enum Phase: Equatable {
        case idle, reading, review, saving, saved
    }

    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    var draft: BloodTestDraft?

    private let client: any BloodTestWriting
    private let tokenProvider: () async throws -> String

    init(client: any BloodTestWriting = BloodTestClient(), tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func readFile(at url: URL) async {
        await read {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                return try BloodReportReader.lines(pdfAt: url)
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw BloodReportReader.Failure.unreadable
            }
            return try BloodReportReader.lines(images: [image])
        }
    }

    func readScan(_ pages: [CGImage]) async {
        await read { try BloodReportReader.lines(images: pages) }
    }

    private func read(_ lines: @escaping @Sendable () throws -> [ReportTextLine]) async {
        phase = .reading
        errorMessage = nil
        do {
            // Recognition takes seconds on a long report: off the main actor.
            let report = try await Task.detached(priority: .userInitiated) {
                BloodReportParser.parse(try lines())
            }.value
            guard !report.results.isEmpty else {
                return fail(String(localized: "Aucun marqueur reconnu dans ce document. Essaie le PDF du laboratoire plutôt qu'une photo."))
            }
            draft = BloodTestDraft(report)
            phase = .review
        } catch {
            fail(String(localized: "Lecture du document impossible."))
        }
    }

    func save() async {
        guard let draft, draft.canSave else { return }
        phase = .saving
        errorMessage = nil
        do {
            try await SharpitRetry.run {
                try await client.createBloodTest(sampledAt: draft.sampledAt, results: draft.inputs, token: try await tokenProvider())
            }
            self.draft = nil
            phase = .saved
        } catch SharpitAPIError.message(let message) {
            errorMessage = message
            phase = .review
        } catch {
            errorMessage = String(localized: "Enregistrement impossible. Réessaie dans un instant.")
            phase = .review
        }
    }

    func discard() {
        draft = nil
        errorMessage = nil
        phase = .idle
    }

    private func fail(_ message: String) {
        errorMessage = message
        phase = .idle
    }
}
