import SwiftUI

@main
struct ShadeTraceMapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("has_completed_onboarding") private var onboardingComplete = false
    /// Not persisted, and dark by default - same as the Flutter app.
    @State private var themeMode = ThemeMode.dark
    @State private var fold = FoldState()
    @State private var language = AppLanguage.shared

    init() {
        LegacyFlutterSettings.migrate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete {
                    RootView(themeMode: $themeMode)
                } else {
                    OnboardingScreen { onboardingComplete = true }
                }
            }
            // Picking a language in Settings rebuilds the screens in it: Text
            // reads the locale from the environment, and the id change makes
            // every screen re-create its code-built text too.
            .id(language.code ?? "system")
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
            .environment(language)
            // One hinge observer for the whole app; every screen reads the
            // posture from the environment.
            .background(HingeObserver(state: fold))
            .environment(fold)
            .preferredColorScheme(themeMode == .system ? nil : themeMode == .dark ? .dark : .light)
            .task { await HomeWidgetSync.sync() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Keeps the widget fresh across day boundaries / location changes.
            if phase == .active { Task { await HomeWidgetSync.sync() } }
        }
    }
}
