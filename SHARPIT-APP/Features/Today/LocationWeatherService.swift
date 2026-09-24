import CoreLocation
import WeatherKit

struct AppleWeatherReading: Codable, Equatable, Sendable {
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
    @ObservationIgnored
    private var hasStarted = false

    init() {
        if let cached = Self.cachedReading() {
            reading = cached.reading
            statusLine = cached.reading.city
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        locator.onDenied = { [weak self] in
            self?.statusLine = "Météo indisponible"
        }
        locator.onFix = { [weak self] location in
            guard let self else { return }
            self.statusLine = "Météo…"
            Task { await self.refresh(from: location) }
        }
        locator.start()
    }

    private func refresh(from location: CLLocation) async {
        async let city = reverseGeocode(location)
        // Only the current conditions: the chip shows nothing else, and the full `weather(for:)`
        // also asks for the minute forecast, which WeatherKit does not serve in France — it
        // logged "Missing minute forecast conditions" on every launch.
        async let weather = WeatherService.shared.weather(for: location, including: .current)

        do {
            let current = try await weather
            let celsius = current.temperature.converted(to: .celsius).value
            reading = AppleWeatherReading(
                city: await city ?? "Ici",
                temperatureCelsius: Int(celsius.rounded()),
                condition: current.condition.description,
                symbolName: current.symbolName
            )
            statusLine = reading?.city ?? "Météo"
            Self.storeCachedReading(reading)
        } catch {
            if reading == nil {
                statusLine = "Météo indisponible"
            }
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

    private struct CachedReading: Codable {
        let reading: AppleWeatherReading
        let savedAt: Date
    }

    private static let cacheKey = "sharpit.weather.current"
    private static let cacheLifetime: TimeInterval = 15 * 60

    private static func cachedReading() -> CachedReading? {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let cached = try? JSONDecoder().decode(CachedReading.self, from: data),
            Date().timeIntervalSince(cached.savedAt) < cacheLifetime
        else {
            return nil
        }
        return cached
    }

    private static func storeCachedReading(_ reading: AppleWeatherReading?) {
        guard let reading else { return }
        let cached = CachedReading(reading: reading, savedAt: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
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
