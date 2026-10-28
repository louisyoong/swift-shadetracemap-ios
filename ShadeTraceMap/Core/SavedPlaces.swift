import Foundation
import Observation

struct SavedPlace: Codable, Identifiable, Hashable {
    var id = UUID()
    let name: String
    let lat: Double
    let lon: Double

    var place: Place { Place(displayName: name, lat: lat, lon: lon) }
}

/// The user's starred places, kept on this device only (a small JSON list in
/// UserDefaults) - no account or server. Shared by every tab's search field,
/// the compass location menu and the golden-hour reminders.
@MainActor
@Observable
final class SavedPlaces {
    static let shared = SavedPlaces()

    private static let storageKey = "saved_places"
    /// Two spots closer than this (~100 m) count as the same place.
    private static let samePlaceDegrees = 0.001

    private(set) var places: [SavedPlace] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let list = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            places = list
        }
    }

    func saved(lat: Double, lon: Double) -> SavedPlace? {
        places.first { abs($0.lat - lat) < Self.samePlaceDegrees && abs($0.lon - lon) < Self.samePlaceDegrees }
    }

    func place(id: UUID) -> SavedPlace? { places.first { $0.id == id } }

    /// Saves the place (newest first), or returns it if it's already saved.
    @discardableResult
    func save(_ place: Place) -> SavedPlace {
        if let existing = saved(lat: place.lat, lon: place.lon) { return existing }
        let new = SavedPlace(name: place.displayName, lat: place.lat, lon: place.lon)
        places.insert(new, at: 0)
        persist()
        return new
    }

    func remove(_ place: SavedPlace) {
        places.removeAll { $0.id == place.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        // A reminder may have been tied to a place that was just removed.
        Task { await GoldenHourReminders.shared.reschedule() }
    }
}
