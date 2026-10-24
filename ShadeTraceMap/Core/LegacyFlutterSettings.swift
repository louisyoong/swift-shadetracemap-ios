import Foundation

/// Carries saved settings over from the Flutter app, which shares this
/// bundle ID. Flutter's shared_preferences stores each key in
/// UserDefaults.standard with a "flutter." prefix, so without this an
/// updated user would see onboarding and the rating prompt again.
enum LegacyFlutterSettings {
    private static let keys = ["has_completed_onboarding", "has_rated_app"]

    static func migrate() {
        let defaults = UserDefaults.standard
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = defaults.object(forKey: "flutter.\(key)") as? Bool {
                defaults.set(value, forKey: key)
            }
        }
    }
}
