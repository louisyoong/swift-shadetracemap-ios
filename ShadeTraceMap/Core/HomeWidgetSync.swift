import Foundation
import WidgetKit

/// Keeps the home-screen widget's sunrise/sunset data in sync with the
/// device's last known location. Natively this is just UserDefaults in the
/// shared App Group plus a WidgetCenter reload - no home_widget plugin.
///
/// Pushes four instants (yesterday's sunset, today's sunrise/sunset,
/// tomorrow's sunrise) so the widget can always count down to whichever
/// event is next. Same keys as the Flutter app, so SunsetWidget.swift is
/// shared unchanged apart from its App Group ID.
enum HomeWidgetSync {
    static let appGroupId = "group.com.shadetracemap.shadetracemap"
    private static let widgetKind = "SunsetWidget"

    @MainActor
    static func sync() async {
        var lat = 3.1412
        var lng = 101.68653
        var label = String(localized: "Kuala Lumpur", bundle: AppLanguage.bundle)
        if let loc = try? await DeviceLocation.shared.current() {
            lat = loc.coordinate.latitude
            lng = loc.coordinate.longitude
            label = String(localized: "My Location", bundle: AppLanguage.bundle)
        }

        let offset = approxUtcOffsetHours(lng)
        let dayStart = localMidnightMs(nowMs(), offsetHours: offset)
        let dayMs = 86_400_000

        func epoch(_ start: Int, _ minutes: Int?) -> String {
            minutes.map { String(start + $0 * 60_000) } ?? ""
        }
        let today = findSunriseSunset(dayStartMs: dayStart, lat: lat, lon: lng)
        let yesterday = findSunriseSunset(dayStartMs: dayStart - dayMs, lat: lat, lon: lng)
        let tomorrow = findSunriseSunset(dayStartMs: dayStart + dayMs, lat: lat, lon: lng)

        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        defaults.set(epoch(dayStart - dayMs, yesterday.sunset), forKey: "prev_sunset_epoch_ms")
        defaults.set(epoch(dayStart, today.sunrise), forKey: "sunrise_epoch_ms")
        defaults.set(epoch(dayStart, today.sunset), forKey: "sunset_epoch_ms")
        defaults.set(epoch(dayStart + dayMs, tomorrow.sunrise), forKey: "next_sunrise_epoch_ms")
        defaults.set(label, forKey: "location_label")
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
