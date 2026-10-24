import SwiftUI

/// Today's sunrise/sunset, sunshine, UV and temperature from Open-Meteo, as a
/// full-bleed gradient hero tinted by how warm or cold it is.
struct WeatherScreen: View {
    @Environment(\.windowSize) private var windowSize
    @Environment(\.colorScheme) private var scheme

    private enum LoadState { case loading, failed, loaded(WeatherData) }

    @State private var lat = 3.1412
    @State private var lng = 101.68653
    @State private var locationLabel = String(localized: "Kuala Lumpur, Malaysia", bundle: AppLanguage.bundle)
    @State private var search = LocationSearchController()
    @State private var state = LoadState.loading
    @State private var loadGen = 0
    @State private var started = false

    var body: some View {
        let isDark = scheme == .dark
        let temp: Double? = if case .loaded(let w) = state { w.temperature } else { nil }

        TimelineView(.animation) { timeline in
            // The gradient itself rotates ±35° back and forth (Flutter's
            // GradientRotation), so the backdrop feels gently alive.
            let angle = (pingPong(timeline.date, period: 6) - 0.5) * 2 * 35
            tempGradient(temp, isDark: isDark, angleDegrees: angle).ignoresSafeArea()
        }
        .overlay {
            VStack(spacing: 0) {
                LocationSearchField(controller: search, onSelect: select, hint: "Check weather for any place worldwide…")
                    .padding(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                    .zIndex(1)
                content(isDark)
                    .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            reload()
            detectDeviceLocation()
        }
    }

    @ViewBuilder
    private func content(_ isDark: Bool) -> some View {
        let tc = textColor(isDark), tm = textMuted(isDark)
        switch state {
        case .loading:
            ProgressView().tint(tc).controlSize(.large)
        case .failed:
            VStack(spacing: 12) {
                Text("Could not load weather.").font(.system(size: 14)).foregroundStyle(tc)
                Button("Retry", action: reload).buttonStyle(.borderedProminent)
            }
            .padding(24)
        case .loaded(let w):
            let hero = VStack(spacing: 0) {
                LocationChip(label: locationLabel, textColor: tc, isDark: isDark)
                Text("\(Int(w.temperature.rounded()))°")
                    .font(.system(size: isCompactHeight(windowSize) ? 76 : 100, weight: .bold))
                    .tracking(-2)
                    .foregroundStyle(tc)
                    .padding(.top, 14)
                Text(weatherCodeDescription(w.weatherCode))
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(tc)
                    .padding(.top, 6)
                Text("Feels like \(Int(w.feelsLike.rounded()))°  •  H:\(Int(w.temperatureMax.rounded()))° L:\(Int(w.temperatureMin.rounded()))°")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(tm)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if useSideBySideLayout(windowSize) {
                HStack(spacing: 0) {
                    hero
                    ScrollView { stats(w, isDark).padding(.trailing, 12).padding(.vertical, 8) }
                        .defaultScrollAnchor(.center)
                        .frame(width: kSidePanelWidth + 20)
                }
            } else {
                VStack(spacing: 0) {
                    hero
                    stats(w, isDark).padding([.horizontal, .bottom], 12)
                }
            }
        }
    }

    private func stats(_ w: WeatherData, _ isDark: Bool) -> some View {
        let tc = textColor(isDark), tm = textMuted(isDark)
        let uv = uvIndexCategory(w.uvIndexMax)
        return VStack(spacing: 18) {
            HStack(spacing: 0) {
                StatTile(icon: "sunrise", label: "SUNRISE", value: w.sunrise ?? "--:--", textColor: tc, textMuted: tm, accent: 0xFFFFB74D)
                StatTile(icon: "moon.stars", label: "SUNSET", value: w.sunset ?? "--:--", textColor: tc, textMuted: tm, accent: 0xFF8B93FF)
                StatTile(icon: "clock.arrow.circlepath", label: "SUNSHINE",
                         value: formatDuration(minutes: w.sunshineSeconds / 60),
                         textColor: tc, textMuted: tm, accent: 0xFFFFB74D)
                StatTile(icon: "sun.max.fill", label: "UV INDEX", value: String(format: "%.1f", w.uvIndexMax),
                         textColor: tc, textMuted: tm, accent: uv.color, valueColor: Color(hex: uv.color))
            }
            Rectangle().fill(tm.opacity(0.18)).frame(height: 1)
            HStack(spacing: 0) {
                StatTile(icon: "thermometer.medium", label: "FEELS LIKE", value: "\(Int(w.feelsLike.rounded()))°",
                         textColor: tc, textMuted: tm, accent: 0xFFFF7043)
                StatTile(icon: "arrow.up", label: "HIGH / LOW",
                         value: "\(Int(w.temperatureMax.rounded()))° / \(Int(w.temperatureMin.rounded()))°",
                         textColor: tc, textMuted: tm, accent: 0xFF64B5F6)
                StatTile(icon: "drop", label: "HUMIDITY", value: "\(w.humidity)%", textColor: tc, textMuted: tm, accent: 0xFF29B6F6)
                StatTile(icon: "wind", label: "WIND", value: "\(Int(w.windSpeed.rounded())) km/h", textColor: tc, textMuted: tm, accent: 0xFF4DB6AC)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .glass(radius: kCardRadius, tint: isDark ? Color(hex: 0xFF15171C) : .white, opacity: isDark ? 0.55 : 0.4)
    }

    /// Cool teal ↔ warm orange by temperature (10°C → 30°C).
    private func tempGradient(_ tempC: Double?, isDark: Bool, angleDegrees: Double) -> some View {
        let coldTop, coldBottom, hotTop, hotBottom: RGBA
        if isDark {
            coldTop = RGBA(0xFF123842); coldBottom = RGBA(0xFF090D12)
            hotTop = RGBA(0xFF8A3A1C); hotBottom = RGBA(0xFF1C0E07)
        } else {
            coldTop = RGBA(0xFF4FB3BF); coldBottom = RGBA(0xFFF1FAFB)
            hotTop = RGBA(0xFFFF8A50); hotBottom = RGBA(0xFFFFF3E0)
        }
        let t = tempC.map { clampD(($0 - 10) / 20, 0, 1) } ?? 0.5
        let colors = [coldTop.lerp(hotTop, t).color, coldBottom.lerp(hotBottom, t).color]
        // Rotate in real pixel space (not unit-point space) so the visible
        // angle is the same on any aspect ratio.
        return GeometryReader { geo in
            let a = toRad(angleDegrees)
            let half = (geo.size.height / 2)
            let dx = sin(a) * half, dy = cos(a) * half
            let w = max(geo.size.width, 1), h = max(geo.size.height, 1)
            Rectangle().fill(.linearGradient(Gradient(colors: colors),
                                             startPoint: UnitPoint(x: 0.5 - dx / w, y: 0.5 - dy / h),
                                             endPoint: UnitPoint(x: 0.5 + dx / w, y: 0.5 + dy / h)))
        }
    }

    private func reload() {
        loadGen += 1
        let gen = loadGen
        state = .loading
        Task {
            let result: LoadState
            do { result = .loaded(try await fetchWeather(lat: lat, lon: lng)) } catch { result = .failed }
            if gen == loadGen { state = result }
        }
    }

    private func select(_ place: Place) {
        lat = place.lat
        lng = place.lon
        locationLabel = place.shortLabel
        search.selected(place.shortLabel)
        reload()
    }

    private func detectDeviceLocation() {
        Task {
            guard let loc = try? await DeviceLocation.shared.current() else { return }
            lat = loc.coordinate.latitude
            lng = loc.coordinate.longitude
            locationLabel = String(localized: "My Location", bundle: AppLanguage.bundle)
            search.selected(String(localized: "My Location", bundle: AppLanguage.bundle))
            reload()
            if let label = await reverseGeocodeLabel(lat: lat, lon: lng) {
                locationLabel = label
                search.selected(label)
            }
        }
    }
}
