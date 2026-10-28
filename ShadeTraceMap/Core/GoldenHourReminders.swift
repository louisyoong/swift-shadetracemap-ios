import Foundation
import Observation
import UserNotifications

/// "Golden hour starts in 30 min" reminders. Entirely on-device: the times
/// come from SunMath and are scheduled as local notifications for the next
/// week, then rescheduled whenever the app becomes active or a setting
/// changes - no server and no push certificate.
@MainActor
@Observable
final class GoldenHourReminders {
    static let shared = GoldenHourReminders()

    static let leadOptions = [15, 30, 60]

    private enum Key {
        static let enabled = "golden_reminders_enabled"
        static let lead = "golden_reminders_lead_minutes"
        static let morning = "golden_reminders_morning"
        static let placeId = "golden_reminders_place_id"
        static let lastLat = "golden_reminders_last_lat"
        static let lastLon = "golden_reminders_last_lon"
    }
    private static let idPrefix = "golden-hour-"
    private static let daysAhead = 7

    private(set) var enabled: Bool
    var leadMinutes: Int { didSet { changed() } }
    var includeMorning: Bool { didSet { changed() } }
    /// nil = the device's current location.
    var placeId: UUID? { didSet { changed() } }
    /// Set when the user turned reminders on but iOS has notifications off.
    private(set) var permissionDenied = false
    /// @Observable runs `didSet` for the assignments in `init` too; this
    /// keeps loading the saved values from saving and rescheduling.
    @ObservationIgnored private var loaded = false

    private init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: Key.enabled)
        let lead = d.integer(forKey: Key.lead)
        leadMinutes = Self.leadOptions.contains(lead) ? lead : 30
        includeMorning = d.bool(forKey: Key.morning)
        placeId = d.string(forKey: Key.placeId).flatMap(UUID.init(uuidString:))
        loaded = true
    }

    /// Turning on asks for notification permission the first time; if it's
    /// refused the switch stays off and `permissionDenied` explains why.
    func setEnabled(_ on: Bool) async {
        if on {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            permissionDenied = !granted
            enabled = granted
        } else {
            permissionDenied = false
            enabled = false
        }
        save()
        await reschedule()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(enabled, forKey: Key.enabled)
        d.set(leadMinutes, forKey: Key.lead)
        d.set(includeMorning, forKey: Key.morning)
        d.set(placeId?.uuidString, forKey: Key.placeId)
    }

    private func changed() {
        guard loaded else { return }
        save()
        Task { await reschedule() }
    }

    /// Replaces every pending golden-hour notification with fresh ones for
    /// the next week at the chosen place.
    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) })
        guard enabled, let target = await resolvePlace() else { return }

        let offset = approxUtcOffsetHours(target.lon)
        let firstDay = localMidnightMs(nowMs(), offsetHours: offset)
        let now = Date()
        for day in 0..<Self.daysAhead {
            let dayStart = firstDay + day * 86_400_000
            let golden = findGoldenHours(dayStartMs: dayStart, lat: target.lat, lon: target.lon)
            var events: [(start: Int?, morning: Bool)] = [(golden.eveningStart, false)]
            if includeMorning { events.append((golden.morningStart, true)) }
            for event in events {
                guard let start = event.start else { continue }
                let fire = Date(timeIntervalSince1970: Double(dayStart + (start - leadMinutes) * 60_000) / 1000)
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = event.morning
                    ? String(localized: "Morning golden hour", bundle: AppLanguage.bundle)
                    : String(localized: "Evening golden hour", bundle: AppLanguage.bundle)
                content.body = String(localized: "Starts in \(leadMinutes) min at \(target.name).", bundle: AppLanguage.bundle)
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let id = "\(Self.idPrefix)\(day)-\(event.morning ? "am" : "pm")"
                let request = UNNotificationRequest(identifier: id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                try? await center.add(request)
            }
        }
    }

    /// The chosen saved place, else the device's location (or the last one
    /// seen, so reminders keep working when a fix isn't available).
    private func resolvePlace() async -> (name: String, lat: Double, lon: Double)? {
        if let placeId, let saved = SavedPlaces.shared.place(id: placeId) {
            return (saved.name, saved.lat, saved.lon)
        }
        let d = UserDefaults.standard
        let name = String(localized: "your location", bundle: AppLanguage.bundle)
        if let loc = try? await DeviceLocation.shared.current() {
            d.set(loc.coordinate.latitude, forKey: Key.lastLat)
            d.set(loc.coordinate.longitude, forKey: Key.lastLon)
            return (name, loc.coordinate.latitude, loc.coordinate.longitude)
        }
        guard d.object(forKey: Key.lastLat) != nil else { return nil }
        return (name, d.double(forKey: Key.lastLat), d.double(forKey: Key.lastLon))
    }
}

/// Shows a reminder as a banner even while the app is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
