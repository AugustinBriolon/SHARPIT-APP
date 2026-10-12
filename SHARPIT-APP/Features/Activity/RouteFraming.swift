import MapKit

/// Whether the expanded map still frames the route: the recentre button only shows when it
/// would do something — the route partly out of view, or lost in a much wider map.
nonisolated enum RouteFraming {
    /// Below this share of the visible span, the route reads as lost in the map.
    static let minimumShare = 0.35

    static func isOffRoute(visible: MKCoordinateRegion, route: [V1ActivityCoordinate]) -> Bool {
        guard let bounds = Bounds(route) else { return false }
        let halfLat = visible.span.latitudeDelta / 2
        let halfLon = visible.span.longitudeDelta / 2
        let contained = bounds.minLat >= visible.center.latitude - halfLat
            && bounds.maxLat <= visible.center.latitude + halfLat
            && bounds.minLon >= visible.center.longitude - halfLon
            && bounds.maxLon <= visible.center.longitude + halfLon
        guard contained else { return true }
        let share = max(
            (bounds.maxLat - bounds.minLat) / max(visible.span.latitudeDelta, .ulpOfOne),
            (bounds.maxLon - bounds.minLon) / max(visible.span.longitudeDelta, .ulpOfOne)
        )
        return share < minimumShare
    }

    /// The region that shows `route` inside the top `visibleHeightShare` of a `viewport`-sized
    /// map, the rest being under the page's panel: the span grows so the route fits that band at
    /// `margin`, and the centre moves south so the route sits in it. Nil without a route.
    static func region(
        for route: [V1ActivityCoordinate],
        viewport: CGSize,
        visibleHeightShare: Double = 1,
        margin: Double = 1.35,
        minimumSpan: Double = 0.008
    ) -> MKCoordinateRegion? {
        guard let bounds = Bounds(route), viewport.width > 0, viewport.height > 0 else { return nil }
        let share = min(max(visibleHeightShare, 0.1), 1)
        let centerLat = (bounds.minLat + bounds.maxLat) / 2
        // Degrees of latitude per degree of longitude on screen at this latitude.
        let aspect = Double(viewport.height / viewport.width) * cos(centerLat * .pi / 180)
        let latSpan = max(
            max(bounds.maxLat - bounds.minLat, minimumSpan) * margin / share,
            max(bounds.maxLon - bounds.minLon, minimumSpan) * margin * aspect
        )
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: centerLat - latSpan * (1 - share) / 2,
                longitude: (bounds.minLon + bounds.maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: latSpan / max(aspect, .ulpOfOne))
        )
    }

    private struct Bounds {
        let minLat, maxLat, minLon, maxLon: Double

        init?(_ route: [V1ActivityCoordinate]) {
            guard let first = route.first else { return nil }
            var minLat = first.latitude, maxLat = first.latitude
            var minLon = first.longitude, maxLon = first.longitude
            for point in route {
                minLat = min(minLat, point.latitude)
                maxLat = max(maxLat, point.latitude)
                minLon = min(minLon, point.longitude)
                maxLon = max(maxLon, point.longitude)
            }
            (self.minLat, self.maxLat, self.minLon, self.maxLon) = (minLat, maxLat, minLon, maxLon)
        }
    }
}
