import CoreLocation
import WeatherKit

struct AppleWeatherReading: Equatable, Sendable {
    var city: String
    var temperatureCelsius: Int
    var condition: String
    var symbolName: String
}

@Observable
final class LocationWeatherService {
    var reading: AppleWeatherReading?
    var statusLine: String = "Météo"

    @ObservationIgnored
    private let locator = LocationFixBroker()

    func start() {
        locator.onDenied = { [weak self] in
            self?.statusLine = "Position off"
        }
        locator.onFix = { [weak self] location in
            guard let self else { return }
            self.statusLine = "Météo…"
            Task { await self.refresh(from: location) }
        }
        locator.start()
    }

    private func refresh(from location: CLLocation) async {
        let city = await reverseGeocode(location) ?? "Ici"
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let current = weather.currentWeather
            let celsius = current.temperature.converted(to: .celsius).value
            reading = AppleWeatherReading(
                city: city,
                temperatureCelsius: Int(celsius.rounded()),
                condition: current.condition.description,
                symbolName: current.symbolName
            )
            statusLine = city
        } catch {
            reading = nil
            statusLine = city
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { marks, _ in
                let city = marks?.first?.locality ?? marks?.first?.name
                continuation.resume(returning: city)
            }
        }
    }
}

private final class LocationFixBroker: NSObject, CLLocationManagerDelegate {
    var onFix: ((CLLocation) -> Void)?
    var onDenied: (() -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        apply(manager.authorizationStatus)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        apply(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onFix?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError _: Error) {
        onDenied?()
    }

    private func apply(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            onDenied?()
        @unknown default:
            onDenied?()
        }
    }
}
