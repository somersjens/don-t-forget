#if os(iOS) || os(visionOS)
import CoreLocation
import Foundation
import Observation
import WeatherKit

struct AgendaWeatherDay: Sendable {
    let date: Date
    let symbolName: String
    let temperature: Int
}

struct AgendaWeatherAttribution: Sendable {
    let darkMarkURL: URL
    let lightMarkURL: URL
    let legalPageURL: URL
}

@Observable
@MainActor
final class AppleWeatherForecastStore {
    static let authenticationError = "weatherkit.authenticationFailed"

    private(set) var days: [Date: AgendaWeatherDay] = [:]
    private(set) var attribution: AgendaWeatherAttribution?
    private(set) var isLoading = false

    func forecast(for date: Date) -> AgendaWeatherDay? {
        days[AppCalendar.startOfDay(date)]
    }

    func reload() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKeys.weatherInAgendaEnabled),
              defaults.object(forKey: SettingsKeys.weatherLatitude) != nil,
              defaults.object(forKey: SettingsKeys.weatherLongitude) != nil else {
            days = [:]
            attribution = nil
            defaults.removeObject(forKey: SettingsKeys.weatherLastError)
            return
        }

        let location = CLLocation(
            latitude: defaults.double(forKey: SettingsKeys.weatherLatitude),
            longitude: defaults.double(forKey: SettingsKeys.weatherLongitude)
        )

        isLoading = true
        defer { isLoading = false }

        do {
            async let dailyRequest = WeatherService.shared.weather(for: location, including: .daily)
            async let attributionRequest = WeatherService.shared.attribution
            let (daily, weatherAttribution) = try await (dailyRequest, attributionRequest)
            days = Dictionary(uniqueKeysWithValues: daily.forecast.map { weather in
                let day = AppCalendar.startOfDay(weather.date)
                return (
                    day,
                    AgendaWeatherDay(
                        date: day,
                        symbolName: weather.symbolName,
                        temperature: Int(weather.highTemperature.value.rounded())
                    )
                )
            })
            attribution = AgendaWeatherAttribution(
                darkMarkURL: weatherAttribution.combinedMarkDarkURL,
                lightMarkURL: weatherAttribution.combinedMarkLightURL,
                legalPageURL: weatherAttribution.legalPageURL
            )
            defaults.removeObject(forKey: SettingsKeys.weatherLastError)
        } catch {
            // A checkbox is the deliberate fallback whenever WeatherKit has no result.
            days = [:]
            attribution = nil
            if Self.isAuthenticationFailure(error) {
                defaults.set(Self.authenticationError, forKey: SettingsKeys.weatherLastError)
            } else {
                defaults.set(error.localizedDescription, forKey: SettingsKeys.weatherLastError)
            }
        }
    }

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        inspectedErrors(from: error).contains { nsError in
            let searchableText = [
                nsError.domain,
                nsError.localizedDescription,
                nsError.localizedFailureReason,
                nsError.localizedRecoverySuggestion
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

            return (nsError.domain.contains("WDSJWTAuthenticatorServiceListener") && nsError.code == 2)
                || searchableText.contains("authentication")
                || searchableText.contains("not authorized")
                || searchableText.contains("jwt")
        }
    }

    private static func inspectedErrors(from error: Error) -> [NSError] {
        var errors: [NSError] = []
        var pending = [error as NSError]

        while let nsError = pending.popLast() {
            errors.append(nsError)

            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                pending.append(underlying)
            }

            if let underlyingErrors = nsError.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
                pending.append(contentsOf: underlyingErrors)
            }
        }

        return errors
    }
}

enum WeatherLocationError: LocalizedError {
    case permissionDenied
    case locationUnavailable
    case placeNotFound

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Locatietoegang is niet toegestaan. Vul hieronder zelf een plaats in."
        case .locationUnavailable:
            "Je huidige locatie kon niet worden bepaald. Probeer opnieuw of vul zelf een plaats in."
        case .placeNotFound:
            "Deze plaats kon niet worden gevonden. Controleer de naam en probeer opnieuw."
        }
    }
}

@MainActor
final class WeatherLocationResolver: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard continuation == nil else { throw WeatherLocationError.locationUnavailable }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.failure(WeatherLocationError.permissionDenied))
            @unknown default:
                finish(.failure(WeatherLocationError.locationUnavailable))
            }
        }
    }

    func geocode(place: String) async throws -> (location: CLLocation, name: String) {
        let query = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw WeatherLocationError.placeNotFound }

        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw WeatherLocationError.placeNotFound
        }

        let name = [placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .reduce(into: [String]()) { values, value in
                if !values.contains(value) { values.append(value) }
            }
            .joined(separator: ", ")
        return (location, name.isEmpty ? query : name)
    }

    func name(for location: CLLocation) async -> String {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return "Huidige locatie"
        }
        return [placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .reduce(into: [String]()) { values, value in
                if !values.contains(value) { values.append(value) }
            }
            .joined(separator: ", ")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(WeatherLocationError.permissionDenied))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(WeatherLocationError.locationUnavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(WeatherLocationError.locationUnavailable))
            return
        }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
#endif
