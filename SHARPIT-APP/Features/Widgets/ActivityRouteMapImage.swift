import MapKit
import UIKit

/// Renders a GPS path into a PNG for the « Dernière activité » widget (no live Map in WidgetKit).
enum ActivityRouteMapImage {
    static func write(
        route: [V1ActivityCoordinate],
        sport: V1ActivityType,
        size: CGSize = CGSize(width: 600, height: 400),
        to directory: URL? = WidgetSnapshotStore.containerURL
    ) async {
        guard route.count >= 2, let directory else { return }
        let safe = route.filter {
            $0.latitude.isFinite && $0.longitude.isFinite
                && abs($0.latitude) <= 90 && abs($0.longitude) <= 180
        }
        guard safe.count >= 2 else { return }

        let coordinates = safe.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard let region = RouteFraming.region(for: safe, viewport: size),
              region.span.latitudeDelta.isFinite,
              region.span.longitudeDelta.isFinite,
              region.span.latitudeDelta > 0,
              region.span.longitudeDelta > 0
        else { return }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.mapType = .standard

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await MKMapSnapshotter(options: options).start()
        } catch {
            return
        }

        let tone = UIColor(
            red: sport.identity.red,
            green: sport.identity.green,
            blue: sport.identity.blue,
            alpha: 1
        )
        let image = UIGraphicsImageRenderer(size: size).image { context in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (index, coordinate) in coordinates.enumerated() {
                let point = snapshot.point(for: coordinate)
                guard point.x.isFinite, point.y.isFinite else { continue }
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            tone.setStroke()
            path.lineWidth = 4
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()

            if let start = coordinates.first {
                let point = snapshot.point(for: start)
                guard point.x.isFinite, point.y.isFinite else { return }
                let marker = UIBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                UIColor.white.setFill()
                marker.fill()
                tone.setStroke()
                marker.lineWidth = 2.5
                marker.stroke()
            }

            let colors = [UIColor.clear.cgColor, UIColor.white.cgColor] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: size.height * 0.55),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
        }

        guard let data = image.pngData() else { return }
        let url = directory.appending(path: WidgetSnapshotStore.lastActivityMapFileName)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Where the athlete trains: kept out of backups like the snapshot beside it.
        BackupExclusion.exclude(url)
    }

    static func erase(in directory: URL? = WidgetSnapshotStore.containerURL) {
        guard let url = directory?.appending(path: WidgetSnapshotStore.lastActivityMapFileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
