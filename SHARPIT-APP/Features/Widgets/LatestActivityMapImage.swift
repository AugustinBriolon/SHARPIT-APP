import CoreImage
import MapKit
import SwiftUI
import UIKit

/// The maps under « Dernière activité »: a widget cannot draw a map, so the app draws them — a
/// quiet map with the route on it, start marked — once per face and per appearance, beside the
/// snapshot in the App Group.
enum LatestActivityMapImage {
    /// Writes every face's map. False when there is no route or one could not be drawn: the
    /// widget then keeps its plain face rather than show half the set.
    static func write(route: [V1ActivityCoordinate], to directory: URL? = WidgetSnapshotStore.containerURL) async -> Bool {
        let coordinates = route
            .filter { $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }
        guard coordinates.count >= 2, directory != nil else { return false }
        for map in WidgetSnapshotStore.LatestActivityMap.allCases {
            for dark in [false, true] {
                guard let url = WidgetSnapshotStore.latestActivityMapURL(map, dark: dark, in: directory),
                      let data = await png(route: coordinates, map: map, dark: dark)
                else { return false }
                do {
                    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                } catch {
                    return false
                }
                // Where the athlete trains: kept out of backups like the snapshot beside it.
                BackupExclusion.exclude(url)
            }
        }
        return true
    }

    /// The map in greys: water and parks keep their shapes and lose their colours, so the only
    /// hue on the face is the route's.
    private static func quiet(_ image: UIImage) -> UIImage {
        guard let input = CIImage(image: image) else { return image }
        let grey = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 0.92])
        guard let rendered = CIContext().createCGImage(grey, from: grey.extent) else { return image }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
    }

    private static func png(route: [V1ActivityCoordinate], map: WidgetSnapshotStore.LatestActivityMap, dark: Bool) async -> Data? {
        // The route sits above the figures: the span grows and the centre moves south for it.
        guard let region = RouteFraming.region(for: route, viewport: map.size, visibleHeightShare: map.routeShare, margin: 1.5),
              region.span.latitudeDelta.isFinite, region.span.longitudeDelta.isFinite
        else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = map.size
        options.scale = 2
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        // Streets and names in grey, no shops or pins: the route is what is read.
        let style = MKStandardMapConfiguration(emphasisStyle: .muted)
        style.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = style
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let line = UIColor(SharpitColor.destructive).resolvedColor(with: options.traitCollection)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: map.size, format: format).pngData { _ in
            quiet(snapshot.image).draw(in: CGRect(origin: .zero, size: map.size))
            let points = route
                .map { snapshot.point(for: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
                .filter { $0.x.isFinite && $0.y.isFinite }
            guard let start = points.first else { return }
            let path = UIBezierPath()
            path.move(to: start)
            points.dropFirst().forEach(path.addLine(to:))
            path.lineWidth = 3.5
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            line.setStroke()
            path.stroke()

            // The start, hollow: where the line ends is where the session ended.
            let marker = UIBezierPath(ovalIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10))
            (dark ? UIColor.black : UIColor.white).setFill()
            marker.fill()
            marker.lineWidth = 2.5
            marker.stroke()
        }
    }
}
