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
            defaults.removeObject(forKey: SettingsKeys.weatherLastErrorDetails)
            return
        }

        let location = CLLocation(
            latitude: defaults.double(forKey: SettingsKeys.weatherLatitude),
            longitude: defaults.double(forKey: SettingsKeys.weatherLongitude)
        )

        isLoading = true
        defer { isLoading = false }

        do {
            let daily = try await WeatherService.shared.weather(for: location, including: .daily)
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
            await reloadAttribution()
            defaults.removeObject(forKey: SettingsKeys.weatherLastError)
            defaults.removeObject(forKey: SettingsKeys.weatherLastErrorDetails)
        } catch {
            days = [:]
            attribution = nil
            if Self.isAuthenticationFailure(error) {
                defaults.set(Self.authenticationError, forKey: SettingsKeys.weatherLastError)
            } else {
                defaults.set(error.localizedDescription, forKey: SettingsKeys.weatherLastError)
            }
            defaults.set(Self.diagnosticDescription(for: error), forKey: SettingsKeys.weatherLastErrorDetails)
        }
    }

    private func reloadAttribution() async {
        do {
            let weatherAttribution = try await WeatherService.shared.attribution
            attribution = AgendaWeatherAttribution(
                darkMarkURL: weatherAttribution.combinedMarkDarkURL,
                lightMarkURL: weatherAttribution.combinedMarkLightURL,
                legalPageURL: weatherAttribution.legalPageURL
            )
        } catch {
            attribution = nil
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

    private static func diagnosticDescription(for error: Error) -> String {
        inspectedErrors(from: error)
            .enumerated()
            .map { index, nsError in
                let message = [
                    nsError.localizedDescription,
                    nsError.localizedFailureReason,
                    nsError.localizedRecoverySuggestion
                ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")

                return "#\(index + 1) \(nsError.domain) \(nsError.code): \(message)"
            }
            .joined(separator: "\n")
    }

    private static func openMeteoForecast(for location: CLLocation) async throws -> [Date: AgendaWeatherDay] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(location.coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(location.coordinate.longitude)"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max"),
            URLQueryItem(name: "timezone", value: TimeZone.current.identifier),
            URLQueryItem(name: "forecast_days", value: "11")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        let forecast = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        if forecast.error == true {
            throw OpenMeteoError.api(forecast.reason ?? "Open-Meteo returned an unknown error.")
        }

        guard let daily = forecast.daily else {
            throw OpenMeteoError.missingDailyForecast
        }

        let dateFormatter = openMeteoDateFormatter(for: forecast.timezone)
        return Dictionary(uniqueKeysWithValues: daily.time.enumerated().compactMap { index, dateString in
            guard let date = dateFormatter.date(from: dateString),
                  daily.temperature2mMax.indices.contains(index),
                  daily.weatherCode.indices.contains(index),
                  let temperature = daily.temperature2mMax[index],
                  let weatherCode = daily.weatherCode[index] else {
                return nil
            }

            let day = AppCalendar.startOfDay(date)
            return (
                day,
                AgendaWeatherDay(
                    date: day,
                    symbolName: symbolName(forOpenMeteoWeatherCode: weatherCode),
                    temperature: Int(temperature.rounded())
                )
            )
        })
    }

    private static func openMeteoDateFormatter(for timezoneIdentifier: String?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let timezoneIdentifier,
           let timeZone = TimeZone(identifier: timezoneIdentifier) {
            formatter.timeZone = timeZone
        } else {
            formatter.timeZone = .current
        }
        return formatter
    }

    private static func symbolName(forOpenMeteoWeatherCode code: Int) -> String {
        switch code {
        case 0:
            return "sun.max.fill"
        case 1:
            return "sun.min.fill"
        case 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55:
            return "cloud.drizzle.fill"
        case 56, 57, 66, 67:
            return "cloud.sleet.fill"
        case 61, 63, 65:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow.fill"
        case 80, 81, 82:
            return "cloud.heavyrain.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    let daily: OpenMeteoDailyForecast?
    let timezone: String?
    let error: Bool?
    let reason: String?
}

private struct OpenMeteoDailyForecast: Decodable {
    let time: [String]
    let weatherCode: [Int?]
    let temperature2mMax: [Double?]

    private enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
    }
}

private enum OpenMeteoError: LocalizedError {
    case api(String)
    case missingDailyForecast

    var errorDescription: String? {
        switch self {
        case .api(let reason):
            return reason
        case .missingDailyForecast:
            return "Open-Meteo response did not include a daily forecast."
        }
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
