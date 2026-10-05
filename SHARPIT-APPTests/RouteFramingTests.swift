import MapKit
import Testing
@testable import Sharpit

@Suite struct RouteFramingTests {
    private let route = [
        V1ActivityCoordinate(latitude: 45.75, longitude: 4.83),
        V1ActivityCoordinate(latitude: 45.77, longitude: 4.85),
    ]

    private func region(lat: Double, lon: Double, span: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    @Test func aFramedRouteNeedsNoButton() {
        #expect(!RouteFraming.isOffRoute(visible: region(lat: 45.76, lon: 4.84, span: 0.03), route: route))
    }

    @Test func aRoutePartlyOutOfViewOrLostInTheMapDoes() {
        #expect(RouteFraming.isOffRoute(visible: region(lat: 45.775, lon: 4.84, span: 0.02), route: route))
        #expect(RouteFraming.isOffRoute(visible: region(lat: 45.76, lon: 4.84, span: 0.2), route: route))
    }

    @Test func noRouteNoButton() {
        #expect(!RouteFraming.isOffRoute(visible: region(lat: 0, lon: 0, span: 1), route: []))
    }
}
