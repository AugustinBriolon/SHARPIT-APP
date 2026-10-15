import ImageIO
import SwiftUI
import UIKit

/// Animated GIF (or still) loaded from a remote URL — form reference for guided sets.
struct GuidedExerciseMediaView: View {
    let url: URL
    var height: CGFloat = 200

    var body: some View {
        AnimatedRemoteGIF(url: url)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(SharpitColor.chipSurface)
            .clipShape(RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    .strokeBorder(SharpitColor.analysisGrid.opacity(0.35), lineWidth: 1)
            )
            .accessibilityLabel("Démonstration de l’exercice")
    }
}

/// Small static thumb for overview rows (JPG — no decode of animated frames).
struct GuidedExerciseThumbView: View {
    let url: URL
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
            case .empty:
                SharpitColor.chipSurface
            @unknown default:
                SharpitColor.chipSurface
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "figure.strengthtraining.traditional")
            .font(SharpitTypography.label)
            .foregroundStyle(SharpitColor.mutedForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SharpitColor.chipSurface)
    }
}

// MARK: - Animated GIF host

private struct AnimatedRemoteGIF: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.backgroundColor = .clear
        context.coordinator.load(url: url, into: view)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.load(url: url, into: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedURL: URL?
        private var task: URLSessionDataTask?

        func load(url: URL, into imageView: UIImageView) {
            task?.cancel()
            loadedURL = url
            if let cached = Self.cache.object(forKey: url as NSURL) {
                imageView.image = cached
                imageView.startAnimating()
                return
            }
            imageView.image = nil
            task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let image = UIImage.animatedGif(data: data) else { return }
                Self.cache.setObject(image, forKey: url as NSURL)
                DispatchQueue.main.async {
                    guard self.loadedURL == url else { return }
                    imageView.image = image
                    imageView.startAnimating()
                }
            }
            task?.resume()
        }

        private static let cache = NSCache<NSURL, UIImage>()
    }
}

private extension UIImage {
    static func animatedGif(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        if count == 1, let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return UIImage(cgImage: cg)
        }

        var frames: [UIImage] = []
        var duration: Double = 0
        frames.reserveCapacity(count)
        for index in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            duration += frameDuration(source: source, index: index)
        }
        guard !frames.isEmpty else { return nil }
        if duration <= 0 { duration = Double(frames.count) * 0.1 }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        let defaults = 0.1
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return defaults }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let value = unclamped ?? clamped ?? defaults
        return value < 0.02 ? defaults : value
    }
}
