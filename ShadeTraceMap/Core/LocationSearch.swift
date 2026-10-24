import Foundation
import Observation

private let nominatimUserAgent = "ShadeTraceMapSwift/1.0 (contact: louis910729@gmail.com)"

/// Place names in the app's own language where OpenStreetMap has them,
/// falling back to English (e.g. "ja,en", "zh-Hant,en").
private var placeLanguage: String {
    let lang = AppLanguage.currentCode
    let osm = lang == "yue-Hant" ? "zh-Hant" : lang
    return osm == "en" ? "en" : "\(osm),en"
}

struct Place: Identifiable, Hashable {
    let id = UUID()
    let displayName: String
    let lat: Double
    let lon: Double

    /// First three comma-separated parts, like the Flutter app's labels.
    var shortLabel: String {
        displayName.split(separator: ",").prefix(3).joined(separator: ",")
    }
}

private func nominatimRequest(_ path: String, _ items: [URLQueryItem]) -> URLRequest {
    var c = URLComponents(string: "https://nominatim.openstreetmap.org/\(path)")!
    c.queryItems = items
    var req = URLRequest(url: c.url!)
    req.setValue(nominatimUserAgent, forHTTPHeaderField: "User-Agent")
    return req
}

/// Reverse-geocodes a lat/lng into a short display label via Nominatim.
/// Returns nil on any failure so callers keep their own default label.
func reverseGeocodeLabel(lat: Double, lon: Double) async -> String? {
    let req = nominatimRequest("reverse", [
        .init(name: "format", value: "json"),
        .init(name: "lat", value: "\(lat)"),
        .init(name: "lon", value: "\(lon)"),
        .init(name: "zoom", value: "14"),
        .init(name: "accept-language", value: placeLanguage),
    ])
    guard let (data, res) = try? await URLSession.shared.data(for: req),
          (res as? HTTPURLResponse)?.statusCode == 200,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let name = json["display_name"] as? String, !name.isEmpty else { return nil }
    return name.split(separator: ",").prefix(3).joined(separator: ",")
}

/// Debounced Nominatim place search, shared by every screen with a
/// "search any place worldwide" field.
@MainActor
@Observable
final class LocationSearchController {
    var text = "" {
        didSet { if text != oldValue && !suppressSearch { onChanged(text) } }
    }
    var results: [Place] = []
    var searching = false

    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var gen = 0
    @ObservationIgnored private var suppressSearch = false

    private func fetchPlaces(_ q: String) async -> [Place] {
        gen += 1
        let myGen = gen
        searching = true
        defer { if myGen == gen { searching = false } }
        let req = nominatimRequest("search", [
            .init(name: "format", value: "json"),
            .init(name: "limit", value: "5"),
            .init(name: "q", value: q),
            .init(name: "accept-language", value: placeLanguage),
        ])
        guard let (data, res) = try? await URLSession.shared.data(for: req) else {
            if myGen == gen { results = [] }
            return []
        }
        guard myGen == gen else { return [] }
        let list = ((res as? HTTPURLResponse)?.statusCode == 200
            ? (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
            : nil) ?? []
        results = list.compactMap { r in
            guard let name = r["display_name"] as? String,
                  let lat = Double("\(r["lat"] ?? "")"),
                  let lon = Double("\(r["lon"] ?? "")") else { return nil }
            return Place(displayName: name, lat: lat, lon: lon)
        }
        return results
    }

    private func onChanged(_ q: String) {
        debounce?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 3 {
            results = []
            return
        }
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            _ = await fetchPlaces(trimmed)
        }
    }

    /// Return submits right away instead of waiting on the debounce.
    func submit(_ onSelect: @escaping (Place) -> Void) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return }
        if let first = results.first {
            onSelect(first)
            return
        }
        debounce?.cancel()
        Task {
            if let first = await fetchPlaces(q).first { onSelect(first) }
        }
    }

    func selected(_ label: String) {
        suppressSearch = true
        text = label
        suppressSearch = false
        results = []
    }

    func clear() {
        debounce?.cancel()
        suppressSearch = true
        text = ""
        suppressSearch = false
        results = []
    }
}
