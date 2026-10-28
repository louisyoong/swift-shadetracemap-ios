import Foundation
import CoreLocation

// Straight port of the Flutter app's lib/sun_math.dart - same formulas,
// same constants, so both apps compute identical sun positions and shadows.

let maxShadowLen = 320.0
let coreMaxOpacity = 0.6
let softMaxOpacity = 0.25

func toRad(_ d: Double) -> Double { d * .pi / 180 }
func toDeg(_ r: Double) -> Double { r * 180 / .pi }

func norm360(_ d: Double) -> Double {
    var d = d.truncatingRemainder(dividingBy: 360)
    if d < 0 { d += 360 }
    return d
}

func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }

func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

struct SunPosition: Equatable {
    let altitude: Double
    let azimuth: Double
}

/// Low-precision astronomical solar position (altitude/azimuth) for a given
/// instant, latitude and longitude. Accurate to a few arc-minutes.
func sunPosition(instantMs: Double, lat: Double, lon: Double) -> SunPosition {
    let jd = instantMs / 86_400_000 + 2_440_587.5
    let n = jd - 2_451_545.0

    let l = norm360(280.46 + 0.9856474 * n)
    let g = norm360(357.528 + 0.9856003 * n)
    let lambda = norm360(l + 1.915 * sin(toRad(g)) + 0.02 * sin(toRad(2 * g)))
    let eps = 23.439 - 0.0000004 * n

    let alpha = norm360(toDeg(atan2(cos(toRad(eps)) * sin(toRad(lambda)), cos(toRad(lambda)))))
    let delta = toDeg(asin(sin(toRad(eps)) * sin(toRad(lambda))))

    let gmst = norm360(280.46061837 + 360.98564736629 * n)
    let h = norm360(gmst + lon - alpha)
    let hn = h > 180 ? h - 360 : h

    let latR = toRad(lat), deltaR = toRad(delta), hr = toRad(hn)
    let altitude = toDeg(asin(sin(latR) * sin(deltaR) + cos(latR) * cos(deltaR) * cos(hr)))
    let azimuth = norm360(
        toDeg(atan2(sin(hr), cos(hr) * sin(latR) - tan(deltaR) * cos(latR))) + 180
    )
    return SunPosition(altitude: altitude, azimuth: azimuth)
}

func sunPosition(_ date: Date, lat: Double, lon: Double) -> SunPosition {
    sunPosition(instantMs: date.timeIntervalSince1970 * 1000, lat: lat, lon: lon)
}

/// Approximate clear-sky direct solar irradiance (W/m²), Meinel & Meinel model.
func solarIrradianceWm2(_ altitudeDeg: Double) -> Double {
    if altitudeDeg <= 0 { return 0 }
    let solarConstant = 1353.0
    let airMass = 1 / sin(toRad(altitudeDeg))
    return solarConstant * pow(0.7, pow(airMass, 0.678))
}

struct SunTimes: Equatable {
    var sunrise: Int?
    var sunset: Int?
}

/// [dayStartMs] must be the absolute instant of local midnight at the
/// location (see localMidnightMs) - not the device's own midnight.
func findSunriseSunset(dayStartMs: Int, lat: Double, lon: Double) -> SunTimes {
    var last: Double?
    var sunrise: Int?
    var sunset: Int?
    for m in stride(from: 0, through: 1440, by: 5) {
        let alt = sunPosition(instantMs: Double(dayStartMs + m * 60_000), lat: lat, lon: lon).altitude
        if let last {
            if last <= 0 && alt > 0 && sunrise == nil { sunrise = m }
            if last > 0 && alt <= 0 && sunset == nil { sunset = m }
        }
        last = alt
    }
    return SunTimes(sunrise: sunrise, sunset: sunset)
}

/// Golden hour: the sun between 6° above and 4° below the horizon, when the
/// light is warm and soft. Minutes after [dayStartMs] (local midnight), like
/// [SunTimes]; nil where the sun never crosses that band (polar days).
struct GoldenHours: Equatable {
    var morningStart: Int?
    var morningEnd: Int?
    var eveningStart: Int?
    var eveningEnd: Int?
}

let goldenHourHighDeg = 6.0
let goldenHourLowDeg = -4.0

func findGoldenHours(dayStartMs: Int, lat: Double, lon: Double) -> GoldenHours {
    var result = GoldenHours()
    var last: Double?
    for m in stride(from: 0, through: 1440, by: 2) {
        let alt = sunPosition(instantMs: Double(dayStartMs + m * 60_000), lat: lat, lon: lon).altitude
        if let last {
            if last <= goldenHourLowDeg && alt > goldenHourLowDeg && result.morningStart == nil { result.morningStart = m }
            if last <= goldenHourHighDeg && alt > goldenHourHighDeg && result.morningEnd == nil { result.morningEnd = m }
            if last > goldenHourHighDeg && alt <= goldenHourHighDeg && result.eveningStart == nil { result.eveningStart = m }
            if last > goldenHourLowDeg && alt <= goldenHourLowDeg && result.eveningEnd == nil { result.eveningEnd = m }
        }
        last = alt
    }
    return result
}

// MARK: - Geo helpers

private let earthR = 6_378_137.0

func metersToLngLat(_ cLng: Double, _ cLat: Double, _ dxE: Double, _ dyN: Double) -> CLLocationCoordinate2D {
    let dLat = (dyN / earthR) * (180 / .pi)
    let dLng = (dxE / (earthR * cos(.pi * cLat / 180))) * (180 / .pi)
    return CLLocationCoordinate2D(latitude: cLat + dLat, longitude: cLng + dLng)
}

func offsetPoint(_ p: CLLocationCoordinate2D, distM: Double, bearingDeg: Double) -> CLLocationCoordinate2D {
    let rad = toRad(bearingDeg)
    return metersToLngLat(p.longitude, p.latitude, distM * sin(rad), distM * cos(rad))
}

/// Andrew's monotone chain convex hull.
func convexHull(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
    let pts = points.sorted {
        $0.longitude != $1.longitude ? $0.longitude < $1.longitude : $0.latitude < $1.latitude
    }
    if pts.count < 3 { return pts }

    func cross(_ o: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        (a.longitude - o.longitude) * (b.latitude - o.latitude) - (a.latitude - o.latitude) * (b.longitude - o.longitude)
    }

    var lower: [CLLocationCoordinate2D] = []
    for p in pts {
        while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
            lower.removeLast()
        }
        lower.append(p)
    }
    var upper: [CLLocationCoordinate2D] = []
    for p in pts.reversed() {
        while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
            upper.removeLast()
        }
        upper.append(p)
    }
    upper.removeLast()
    lower.removeLast()
    return lower + upper
}

func buildingHeight(of attributes: [String: Any]) -> Double {
    func num(_ key: String) -> Double? { (attributes[key] as? NSNumber)?.doubleValue }
    var h: Double?
    if let v = num("render_height") {
        h = v
    } else if let v = num("height") {
        h = v
    } else if let v = num("levels") {
        h = v * 3
    }
    var height = h ?? 12
    if height <= 0 { height = 12 }
    return height
}

// MARK: - Location-local wall-clock helpers
// A location's UTC offset is approximated from its longitude (15° ≈ 1 hour),
// same as the Flutter app.

func approxUtcOffsetHours(_ lon: Double) -> Int {
    Int(clampD((lon / 15).rounded(), -12, 14))
}

struct LocalFields {
    let year: Int
    let month: Int
    let day: Int
    let minutesOfDay: Int
}

private var utcCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

func localFieldsFromInstant(_ instantMs: Int, offsetHours: Int) -> LocalFields {
    let shifted = Date(timeIntervalSince1970: Double(instantMs + offsetHours * 3_600_000) / 1000)
    let c = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: shifted)
    return LocalFields(year: c.year!, month: c.month!, day: c.day!, minutesOfDay: c.hour! * 60 + c.minute!)
}

func dateString(from f: LocalFields) -> String { "\(f.year)-\(pad2(f.month))-\(pad2(f.day))" }

func instantFromLocalFields(year: Int, month: Int, day: Int, minutesOfDay: Int, offsetHours: Int) -> Int {
    let midnight = utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    let midnightMs = Int(midnight.timeIntervalSince1970 * 1000)
    return midnightMs + minutesOfDay * 60_000 - offsetHours * 3_600_000
}

/// Parses "yyyy-MM-dd" into (year, month, day).
func dateParts(_ dateStr: String) -> (Int, Int, Int) {
    let p = dateStr.split(separator: "-").compactMap { Int($0) }
    return (p[0], p[1], p[2])
}

func instantMs(dateStr: String, minutes: Int, offsetHours: Int) -> Int {
    let (y, m, d) = dateParts(dateStr)
    return instantFromLocalFields(year: y, month: m, day: d, minutesOfDay: minutes, offsetHours: offsetHours)
}

func localMidnightMs(_ instantMs: Int, offsetHours: Int) -> Int {
    let dayMs = 86_400_000.0
    let shifted = Double(instantMs + offsetHours * 3_600_000)
    return Int((shifted / dayMs).rounded(.down) * dayMs) - offsetHours * 3_600_000
}

func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

// MARK: - Localized time text
// English keeps the Flutter app's exact formats ("6:30 AM", "6AM", "6A");
// every other language uses its own clock style via the locale (24-hour
// "18:30" in German/French, "午後6:30" in Japanese, "오후 6:30" in Korean…).

private var usesEnglishFormats: Bool { AppLanguage.currentCode.hasPrefix("en") }

private var timeFormatters: [String: DateFormatter] = [:]

/// Formats a location-local minute-of-day with a locale-aware template.
private func localizedTime(_ mins: Int, template: String) -> String {
    let cacheKey = "\(AppLanguage.currentCode)|\(template)"
    let f: DateFormatter
    if let cached = timeFormatters[cacheKey] {
        f = cached
    } else {
        f = DateFormatter()
        f.locale = AppLanguage.currentLocale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        timeFormatters[cacheKey] = f
    }
    return f.string(from: Date(timeIntervalSince1970: Double(mins % 1440) * 60))
}

func formatBigTime(_ mins: Int) -> String {
    guard usesEnglishFormats else { return localizedTime(mins, template: "jmm") }
    let h = mins / 60, m = mins % 60
    let display = h % 12 == 0 ? 12 : h % 12
    return "\(display):\(pad2(m)) \(h < 12 ? "AM" : "PM")"
}

/// Tick labels under the time slider: "6AM" / "6:30AM" in English.
func formatTickTime(_ mins: Int) -> String {
    let m = mins % 1440
    let h = m / 60, mm = m % 60
    guard usesEnglishFormats else { return localizedTime(m, template: mm == 0 ? "j" : "jmm") }
    let display = h % 12 == 0 ? 12 : h % 12
    let ampm = h < 12 ? "AM" : "PM"
    return mm == 0 ? "\(display)\(ampm)" : "\(display):\(pad2(mm))\(ampm)"
}

/// Compact hour labels on the sun-arc chart: "6A" / "12P" in English.
func formatArcHour(_ mins: Int) -> String {
    let h = mins / 60
    guard usesEnglishFormats else { return localizedTime(mins, template: "j") }
    return h == 0 || h == 24 ? "12A" : h == 12 ? "12P" : h < 12 ? "\(h)A" : "\(h - 12)P"
}

/// "6h 25m" in English, "6 Std. 25 Min." in German, "6時間25分" in Japanese…
func formatDuration(minutes: Int) -> String {
    guard !usesEnglishFormats else { return "\(minutes / 60)h \(pad2(minutes % 60))m" }
    let f = DateComponentsFormatter()
    f.allowedUnits = [.hour, .minute]
    f.unitsStyle = .abbreviated
    f.zeroFormattingBehavior = .dropLeading
    var calendar = Calendar.current
    calendar.locale = AppLanguage.currentLocale
    f.calendar = calendar
    return f.string(from: TimeInterval(minutes * 60)) ?? ""
}

func formatHHmm(_ mins: Int?) -> String {
    guard let mins else { return "--:--" }
    return "\(pad2(mins / 60)):\(pad2(mins % 60))"
}
