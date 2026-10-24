import SwiftUI
import Testing
import UIKit

/// Screen snapshots without a dependency: the view is hosted in a real window (its `onAppear`
/// runs, UIKit-backed parts draw), captured at 2×, and compared with the PNG kept in
/// `__Snapshots__` beside this file. A missing reference is recorded and the test fails once;
/// `TEST_RUNNER_SNAPSHOT_RECORD=1` re-records them all. A few stray pixels are tolerated so a
/// simulator's font rasterising does not fail CI; a moved or recoloured element does.
@MainActor
func assertSnapshot<V: View>(
    _ view: V,
    named name: String,
    width: CGFloat = 390,
    style: UIUserInterfaceStyle = .light,
    filePath: String = #filePath,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let image = try await render(view, width: width, style: style)
    let fileName = "\(name)-\(style == .dark ? "dark" : "light").png"
    let reference = URL(filePath: filePath)
        .deletingLastPathComponent()
        .appending(path: "__Snapshots__/\(fileName)")
    let png = try #require(image.pngData(), sourceLocation: sourceLocation)

    let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    guard !record, let stored = UIImage(contentsOfFile: reference.path(percentEncoded: false)) else {
        try FileManager.default.createDirectory(at: reference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: reference)
        Issue.record("Recorded \(fileName); run again to compare.", sourceLocation: sourceLocation)
        return
    }

    let difference = SnapshotDifference(stored, image)
    if difference.share > SnapshotDifference.tolerance {
        let actual = FileManager.default.temporaryDirectory.appending(path: fileName)
        try png.write(to: actual)
        Issue.record(
            "\(fileName) differs from its reference (\(difference.description)); actual at \(actual.path(percentEncoded: false))",
            sourceLocation: sourceLocation
        )
    }
}

@MainActor
private func render<V: View>(_ view: V, width: CGFloat, style: UIUserInterfaceStyle) async throws -> UIImage {
    let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let host = UIHostingController(
        rootView: view
            .frame(width: width)
            .transaction { $0.animation = nil }
    )
    host.overrideUserInterfaceStyle = style
    // No status bar or home indicator: they offset the content and blur its top edge.
    host.safeAreaRegions = []
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: host.sizeThatFits(in: CGSize(width: width, height: 4_000)))
    window.overrideUserInterfaceStyle = style
    window.rootViewController = host
    window.isHidden = false
    defer { window.isHidden = true }
    // A beat for `onAppear` and the first layout pass, then measured again: content built on
    // appearing (a card's curves) grows the view after the first measure.
    try await Task.sleep(for: .milliseconds(400))
    let size = host.sizeThatFits(in: CGSize(width: width, height: 4_000))
    window.frame = CGRect(origin: .zero, size: size)
    window.layoutIfNeeded()
    try await Task.sleep(for: .milliseconds(200))

    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
    }
}

/// The share of pixels that moved by more than a rasterising wobble.
private struct SnapshotDifference: CustomStringConvertible {
    /// 0.5 % of the pixels: anti-aliasing noise passes, a moved chip or a recoloured row does not.
    static let tolerance = 0.005

    let share: Double
    let description: String

    init(_ reference: UIImage, _ actual: UIImage) {
        guard let lhs = Self.pixels(reference), let rhs = Self.pixels(actual), lhs.size == rhs.size else {
            share = 1
            description = "size \(reference.size) vs \(actual.size)"
            return
        }
        var changed = 0
        for index in stride(from: 0, to: lhs.bytes.count, by: 4) {
            let delta = (0..<3).map { abs(Int(lhs.bytes[index + $0]) - Int(rhs.bytes[index + $0])) }.max() ?? 0
            if delta > 24 { changed += 1 }
        }
        share = Double(changed) / Double(lhs.bytes.count / 4)
        description = String(format: "%.2f %% of pixels", share * 100)
    }

    private static func pixels(_ image: UIImage) -> (bytes: [UInt8], size: CGSize)? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (bytes, CGSize(width: width, height: height)) : nil
    }
}
