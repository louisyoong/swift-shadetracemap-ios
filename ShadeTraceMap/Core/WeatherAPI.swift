import Foundation

/// Today's sunrise/sunset, sunshine duration, UV index and temperature for a
/// location, from Open-Meteo's free forecast API (no API key required).
struct WeatherData {
    /// Location-local "HH:mm" (Open-Meteo returns local wall-clock times
    /// with `timezone=auto`, so the hour/minute can be read straight off).
    let sunrise: String?
    let sunset: String?
    let sunshineSeconds: Int
    let uvIndexMax: Double
    let temperature: Double
    let weatherCode: Int
    let feelsLike: Double
    let humidity: Int
    let windSpeed: Double
    let temperatureMax: Double
    let temperatureMin: Double
}

enum WeatherError: Error { case badStatus(Int), badPayload }

func fetchWeather(lat: Double, lon: Double) async throws -> WeatherData {
    var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    c.queryItems = [
        .init(name: "latitude", value: "\(lat)"),
        .init(name: "longitude", value: "\(lon)"),
        .init(name: "daily", value: "sunrise,sunset,sunshine_duration,uv_index_max,temperature_2m_max,temperature_2m_min"),
        .init(name: "current", value: "temperature_2m,weather_code,apparent_temperature,relative_humidity_2m,wind_speed_10m"),
        .init(name: "forecast_days", value: "1"),
        .init(name: "timezone", value: "auto"),
    ]
    let (data, response) = try await URLSession.shared.data(from: c.url!)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw WeatherError.badStatus(status) }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let daily = json["daily"] as? [String: Any],
          let current = json["current"] as? [String: Any] else { throw WeatherError.badPayload }

    func time(_ key: String) -> String? {
        guard let s = (daily[key] as? [Any])?.first as? String, let t = s.split(separator: "T").last else { return nil }
        return String(t.prefix(5))
    }
    func firstDouble(_ key: String) -> Double {
        ((daily[key] as? [Any])?.first as? NSNumber)?.doubleValue ?? 0
    }
    func cur(_ key: String) -> Double { (current[key] as? NSNumber)?.doubleValue ?? 0 }

    return WeatherData(
        sunrise: time("sunrise"),
        sunset: time("sunset"),
        sunshineSeconds: Int(firstDouble("sunshine_duration").rounded()),
        uvIndexMax: firstDouble("uv_index_max"),
        temperature: cur("temperature_2m"),
        weatherCode: Int(cur("weather_code")),
        feelsLike: cur("apparent_temperature"),
        humidity: Int(cur("relative_humidity_2m")),
        windSpeed: cur("wind_speed_10m"),
        temperatureMax: firstDouble("temperature_2m_max"),
        temperatureMin: firstDouble("temperature_2m_min")
    )
}

/// Open-Meteo/WMO weather-code table, condensed to short phrases.
func weatherCodeDescription(_ code: Int) -> String {
    switch code {
    case 0: return String(localized: "Clear and sunny", bundle: AppLanguage.bundle)
    case 1: return String(localized: "Mainly clear", bundle: AppLanguage.bundle)
    case 2: return String(localized: "Partly cloudy", bundle: AppLanguage.bundle)
    case 3: return String(localized: "Overcast", bundle: AppLanguage.bundle)
    case 45, 48: return String(localized: "Foggy", bundle: AppLanguage.bundle)
    case 51, 53, 55: return String(localized: "Drizzle", bundle: AppLanguage.bundle)
    case 56, 57: return String(localized: "Freezing drizzle", bundle: AppLanguage.bundle)
    case 61, 63: return String(localized: "Rain", bundle: AppLanguage.bundle)
    case 65: return String(localized: "Heavy rain", bundle: AppLanguage.bundle)
    case 66, 67: return String(localized: "Freezing rain", bundle: AppLanguage.bundle)
    case 71, 73, 75, 77: return String(localized: "Snow", bundle: AppLanguage.bundle)
    case 80, 81: return String(localized: "Rain showers", bundle: AppLanguage.bundle)
    case 82: return String(localized: "Heavy rain showers", bundle: AppLanguage.bundle)
    case 85, 86: return String(localized: "Snow showers", bundle: AppLanguage.bundle)
    case 95: return String(localized: "Thunderstorm", bundle: AppLanguage.bundle)
    case 96, 99: return String(localized: "Thunderstorm with hail", bundle: AppLanguage.bundle)
    default: return String(localized: "Unsettled weather", bundle: AppLanguage.bundle)
    }
}

/// EPA/WHO UV index scale.
func uvIndexCategory(_ uv: Double) -> (label: String, color: UInt32) {
    if uv < 3 { return ("Low", 0xFF4CAF50) }
    if uv < 6 { return ("Moderate", 0xFFFFC107) }
    if uv < 8 { return ("High", 0xFFFF9800) }
    if uv < 11 { return ("Very High", 0xFFF4511E) }
    return ("Extreme", 0xFF9C27B0)
}
