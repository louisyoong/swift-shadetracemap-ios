import SwiftUI

private enum Tab: Int, CaseIterable { case map, sunPath, compass, weather, settings }

/// Computed so the labels follow a language change in Settings.
private var tabItems: [TabBarItem] { [
    TabBarItem(id: Tab.map.rawValue, icon: "map", label: String(localized: "ShadeMap", bundle: AppLanguage.bundle)),
    TabBarItem(id: Tab.sunPath.rawValue, icon: "sun.max", label: String(localized: "Sun Path", bundle: AppLanguage.bundle)),
    TabBarItem(id: Tab.compass.rawValue, icon: "safari", label: String(localized: "Compass", bundle: AppLanguage.bundle)),
    TabBarItem(id: Tab.weather.rawValue, icon: "cloud", label: String(localized: "Weather", bundle: AppLanguage.bundle)),
    TabBarItem(id: Tab.settings.rawValue, icon: "gearshape", label: String(localized: "Settings", bundle: AppLanguage.bundle)),
] }

/// The five tabs.
///
/// Normally the app shows its own glass tab bar (AppTabBar), a port of the
/// Flutter bar with the same colors - the native iOS 26+ bar can't be
/// recolored that way.
///
/// On iPhone Duo, when iOS wants bars in the side column (outer display, and
/// inner display in landscape), the same bar is drawn vertically in that
/// column. iOS says which side the column is on (`verticalBarEdge`) and where
/// the camera is (occlusion regions), so nothing is guessed - the Flutter app
/// hard-codes both in root_shell.dart.
struct RootView: View {
    @Environment(FoldState.self) private var fold
    @Environment(\.layoutDirection) private var layoutDirection
    @Binding var themeMode: ThemeMode

    @State private var tab = RootView.initialTab
    @State private var windowSize = CGSize(width: 390, height: 844)
    @State private var showRating = false
    @State private var safeInsets = EdgeInsets()
    @State private var cameraRects: [CGRect] = []

    /// The tab to open on. Survives the rebuild after a language change in
    /// Settings, so the user stays on Settings instead of jumping to the map.
    private static var lastTab: Tab = {
        #if DEBUG
        // Debug builds only: launch with START_TAB=<0-4> to open on a tab.
        if let raw = ProcessInfo.processInfo.environment["START_TAB"], let i = Int(raw), let t = Tab(rawValue: i) { return t }
        #endif
        return .map
    }()
    private static var initialTab: Tab { lastTab }

    private var compact: Bool { isCompactHeight(windowSize) }
    private var sideEdge: HorizontalEdge? { fold.verticalBarEdge }

    /// The side column: the system's inset, widened only if too narrow for the bar.
    private var sideColumnWidth: CGFloat {
        guard let edge = sideEdge else { return 0 }
        let inset = edge == .trailing ? safeInsets.trailing : safeInsets.leading
        return max(inset, AppTabBar.verticalWidth + 12)
    }

    var body: some View {
        TabView(selection: $tab) {
            page(ShadeMapScreen(), .map)
            page(SunPathScreen(), .sunPath)
            page(CompassScreen(), .compass)
            page(WeatherScreen(), .weather)
            page(SettingsScreen(themeMode: $themeMode), .settings)
        }
        .tint(AppTabBarStyle.accent)
        .overlay(alignment: .bottom) {
            if sideEdge == nil {
                AppTabBar(items: tabItems, selected: tab.rawValue, compact: compact) { i in
                    tab = Tab(rawValue: i) ?? .map
                }
            }
        }
        .overlay {
            if let edge = sideEdge { sideBar(edge) }
        }
        .environment(\.windowSize, windowSize)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { windowSize = geo.size }
                    .onChange(of: geo.size) { _, size in windowSize = size }
            }
            .ignoresSafeArea()
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { safeInsets = geo.safeAreaInsets }
                    .onChange(of: geo.safeAreaInsets) { _, insets in safeInsets = insets }
            }
        }
        .background(OcclusionReader { cameraRects = $0 }.ignoresSafeArea())
        .onChange(of: tab) { _, newTab in
            RootView.lastTab = newTab
            if newTab == .settings && !AppRating.hasRated { showRating = true }
        }
        .overlay {
            if showRating { RatingDialog(isPresented: $showRating) }
        }
    }

    /// One tab page. The native bar is always hidden; the page's safe area
    /// grows by the custom bar's size (bottom, or the side column if that's
    /// wider than the system's own inset), so each screen's panels stay clear
    /// of it while the map still runs underneath (like Flutter's `extendBody`).
    private func page<V: View>(_ content: V, _ t: Tab) -> some View {
        let item = tabItems[t.rawValue]
        let edge = sideEdge
        let inset = edge == .trailing ? safeInsets.trailing : safeInsets.leading
        let extraSide = edge == nil ? 0 : max(0, sideColumnWidth - inset)
        return content
            .safeAreaPadding(.bottom, edge == nil ? AppTabBar.totalHeight(compact: compact) : 0)
            .safeAreaPadding(edge == .leading ? .leading : .trailing, extraSide)
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label(item.label, systemImage: item.icon) }
            .tag(t)
    }

    /// The vertical bar in the iPhone Duo side column. Centered on the camera
    /// when it shares the column (Apple's HIG lines side controls up with
    /// it), otherwise centered in the column. Sits at the bottom, like the
    /// screens' own floating controls, unless the camera is at that end.
    private func sideBar(_ edge: HorizontalEdge) -> some View {
        let column = sideColumnWidth
        // `edge` is leading/trailing; in Arabic, trailing is the left side.
        let onRight = (edge == .trailing) == (layoutDirection == .leftToRight)
        let columnMinX = onRight ? windowSize.width - column : 0
        let camera = cameraRects.first { $0.midX >= columnMinX && $0.midX <= columnMinX + column }
        let centerX = camera?.midX ?? (columnMinX + column / 2)
        let barHeight = CGFloat(tabItems.count) * (44 + 8) + 12
        let cameraAtBottom = camera.map { $0.midY > windowSize.height / 2 } ?? false
        let centerY = cameraAtBottom
            ? safeInsets.top + 12 + barHeight / 2
            : windowSize.height - safeInsets.bottom - 12 - barHeight / 2
        return AppTabBar(items: tabItems, selected: tab.rawValue, compact: false, vertical: true) { i in
            tab = Tab(rawValue: i) ?? .map
        }
        .position(x: centerX, y: centerY)
        .ignoresSafeArea()
        // Positions above are physical (left-origin) coordinates.
        .environment(\.layoutDirection, .leftToRight)
    }
}
