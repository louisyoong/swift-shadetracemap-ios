import SwiftUI
import Observation

/// The app's display language, chosen in Settings. `nil` follows the
/// device (or the per-app language picked in the iOS Settings app).
///
/// Switches live: SwiftUI `Text` resolves translations through the
/// `\.locale` environment, and every `String(localized:)` in the app passes
/// `AppLanguage.bundle`, so both read the chosen language's .lproj.
@MainActor
@Observable
final class AppLanguage {
    static let shared = AppLanguage()

    /// Same order as requested; each name is written in its own language.
    static let options: [(code: String, name: String)] = [
        ("en", "English"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("ko", "한국어"),
        ("ja", "日本語"),
        ("zh-Hant", "繁體中文"),
        ("zh-Hans", "简体中文"),
        ("pt", "Português"),
        ("ar", "العربية"),
        ("id", "Bahasa Indonesia"),
        ("ru", "Русский"),
        ("yue-Hant", "粵語"),
        ("la", "Latina"),
        ("ss", "SiSwati"),
        ("es", "Español"),
        ("da", "Dansk"),
        ("ms", "Bahasa Melayu"),
    ]

    private static let storageKey = "app_language"
    private static let deviceLanguagesKey = "device_languages"

    /// nil = follow the device.
    private(set) var code: String?

    private init() {
        code = UserDefaults.standard.string(forKey: Self.storageKey)
        if code == nil {
            // Only trustworthy when no in-app choice is active: while one is,
            // iOS reports the chosen language for the whole session.
            UserDefaults.standard.set(Locale.preferredLanguages, forKey: Self.deviceLanguagesKey)
        }
        Self.cache(code)
    }

    func set(_ newCode: String?) {
        guard newCode != code else { return }
        code = newCode
        let defaults = UserDefaults.standard
        if let newCode {
            defaults.set(newCode, forKey: Self.storageKey)
            // The same key the iOS Settings app writes for its per-app
            // language picker, so system UI follows on the next launch too.
            defaults.set([newCode], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: "AppleLanguages")
        }
        Self.cache(newCode)
    }

    /// The language actually shown (the device's resolved one when following it).
    var effectiveCode: String { Self.cachedCode }

    var locale: Locale { Locale(identifier: Self.cachedCode) }

    var layoutDirection: LayoutDirection {
        Locale.Language(identifier: effectiveCode).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    // MARK: - Lookups usable from any thread / non-view code

    nonisolated(unsafe) private static var cachedBundle: Bundle = .main
    nonisolated(unsafe) private static var cachedCode: String = "en"

    private static func cache(_ code: String?) {
        let resolved = code ?? deviceLanguage()
        cachedCode = resolved
        cachedBundle = Bundle.main.path(forResource: resolved, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
    }

    /// The phone's own language (Settings > General > Language), best
    /// matched to the languages this app has. Uses the list saved at the
    /// last launch without an in-app choice, because once a language is
    /// chosen iOS reports only that one until the app restarts.
    private static func deviceLanguage() -> String {
        let preferences = UserDefaults.standard.stringArray(forKey: deviceLanguagesKey) ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferences)
            .first { $0 != "Base" } ?? "en"
    }

    /// Pass to `String(localized:bundle:)` so code-built text follows the choice.
    nonisolated static var bundle: Bundle { cachedBundle }
    /// Resolved language code, e.g. "ja" or "zh-Hant".
    nonisolated static var currentCode: String { cachedCode }
    nonisolated static var currentLocale: Locale { Locale(identifier: cachedCode) }
}
