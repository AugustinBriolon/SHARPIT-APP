import CoreGraphics
import Foundation
import PDFKit
import Vision

/// Turns a report into positioned text, on the device: the PDF's own text layer when it has one,
/// Vision's recognition for a scan or a photo. Nothing here touches the network, and the document
/// is only ever read — never copied, cached or sent (SHARPIT ADR-128).
nonisolated enum BloodReportReader {
    enum Failure: Error {
        case unreadable
    }

    static func lines(pdfAt url: URL) throws -> [ReportTextLine] {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
        var lines: [ReportTextLine] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let layer = textLayer(of: page, index: index)
            lines += layer.isEmpty ? try recognised(in: rendered(page), page: index) : layer
        }
        return lines
    }

    static func lines(images: [CGImage]) throws -> [ReportTextLine] {
        try images.enumerated().flatMap { index, image in try recognised(in: image, page: index) }
    }

    // MARK: PDF text layer

    private static func textLayer(of page: PDFPage, index: Int) -> [ReportTextLine] {
        guard let selection = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        return selection.selectionsByLine().compactMap { line in
            guard let text = line.string, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let bounds = line.bounds(for: page)
            return ReportTextLine(text: text, page: index, midY: bounds.midY, minX: bounds.minX,
                                  height: bounds.height, confidence: 1)
        }
    }

    // MARK: Recognition

    /// A scanned page drawn at three times its point size (about 216 dpi), enough for 8 pt print.
    static func rendered(_ page: PDFPage) throws -> CGImage {
        let scale = 3.0
        let bounds = page.bounds(for: .mediaBox)
        guard let context = CGContext(
            data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure.unreadable }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { throw Failure.unreadable }
        return image
    }

    private static func recognised(in image: CGImage, page: Int) throws -> [ReportTextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR", "en-US"]
        // Correction rewrites what it takes for words: figures and units must come out as printed.
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return ReportTextLine(text: candidate.string, page: page, midY: box.midY, minX: box.minX,
                                  height: box.height, confidence: Double(candidate.confidence))
        }
    }
}
