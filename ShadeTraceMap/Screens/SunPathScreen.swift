import SwiftUI

private let initialLat = 3.1412
private let initialLng = 101.68653
private let stepMinutes = 8

/// A standalone sun-path simulator: scrub date/time/location and see the
/// sun's full-day journey as a golden arc plus where "now" sits on it.
struct SunPathScreen: View {
    @Environment(FoldState.self) private var fold
    @Environment(\.windowSize) private var windowSize
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var lat = initialLat
    @State private var lng = initialLng
    @State private var utcOffsetHours = 8
    @State private var locationLabel = String(localized: "Kuala Lumpur, Malaysia", bundle: AppLanguage.bundle)
    @State private var dateStr: String
    @State private var minutes: Int
    @State private var playing = false
    @State private var playTimer: Timer?
    @State private var search = LocationSearchController()
    @State private var dayAltitudes: [Double] = []
    @State private var sunTimes = SunTimes()
    @State private var goldenHours = GoldenHours()
    @State private var lastPathKey = ""
    @State private var showDatePicker = false
    /// Where the fold crosses this screen (reserved-region API), if anywhere.
    @State private var foldRect: CGRect?

    init() {
        let f = localFieldsFromInstant(nowMs(), offsetHours: 8)
        _dateStr = State(initialValue: dateString(from: f))
        _minutes = State(initialValue: f.minutesOfDay)
    }

    private var currentInstantMs: Int { instantMs(dateStr: dateStr, minutes: minutes, offsetHours: utcOffsetHours) }

    var body: some View {
        let isDark = scheme == .dark
        let pos = sunPosition(instantMs: Double(currentInstantMs), lat: lat, lon: lng)
        let tint = sunTint(pos.altitude, isDark: isDark)
        let sideBySide = useSideBySideLayout(windowSize)
        let halfFolded = fold.posture == .halfFolded

        Group {
            if halfFolded {
                // Half-folded iPhone Duo: split at the fold itself - sun arc on
                // one half, time controls on the other - like a laptop or book.
                GeometryReader { geo in
                    splitAtFold(size: geo.size,
                                first: VStack(spacing: 0) { searchBar; chip(isDark); arcPanel(pos, isDark, sideBySide: true) },
                                second: ScrollView { controls(pos, isDark, inset: .halfFolded) }
                                    .scrollBounceBehavior(.basedOnSize)
                                    .defaultScrollAnchor(.center))
                        .background(FoldDivisionReader(posture: fold.posture) { foldRect = $0 })
                }
            } else if sideBySide {
                VStack(spacing: 0) {
                    searchBar
                    chip(isDark)
                    HStack(alignment: .top, spacing: 0) {
                        arcPanel(pos, isDark, sideBySide: true)
                        ScrollView { controls(pos, isDark, inset: .side) }
                            .frame(width: kSidePanelWidth)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    searchBar
                    chip(isDark)
                    arcPanel(pos, isDark, sideBySide: false)
                    controls(pos, isDark, inset: .stacked)
                }
            }
        }
        .background(LinearGradient(colors: [tint.top.color, tint.bottom.color], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onAppear {
            recomputeDayPath()
            detectDeviceLocation()
        }
        .onChange(of: dateStr) { recomputeDayPath() }
        .sheet(isPresented: $showDatePicker) { datePickerSheet }
    }

    // MARK: - Pieces

    private var searchBar: some View {
        LocationSearchField(controller: search, onSelect: select, hint: "Simulate any place worldwide…",
                            current: Place(displayName: locationLabel, lat: lat, lon: lng))
            .padding(EdgeInsets(top: 12, leading: 12, bottom: 8, trailing: 12))
            .zIndex(1)
    }

    private func chip(_ isDark: Bool) -> some View {
        LocationChip(label: locationLabel, textColor: textColor(isDark), isDark: isDark)
            .padding(.horizontal, 12)
    }

    private func daylightText() -> String? {
        guard let sr = sunTimes.sunrise, let ss = sunTimes.sunset, ss > sr else { return nil }
        let mins = ss - sr
        return String(localized: "\(formatDuration(minutes: mins)) of daylight", bundle: AppLanguage.bundle)
    }

    private func arcPanel(_ pos: SunPosition, _ isDark: Bool, sideBySide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("TODAY'S SUN PATH", color: textMuted(isDark))
                Spacer(minLength: 8)
                if let text = daylightText() {
                    Text(text).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(textMuted(isDark)).lineLimit(1)
                }
            }
            SunArc(altitudes: dayAltitudes, nowMinutes: minutes, sunPos: pos, sunTimes: sunTimes,
                   labelColor: textMuted(isDark), isDark: isDark)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 12))
        .glass(radius: kCardRadius, tint: isDark ? Color(hex: 0xFF15171C) : .white, opacity: 0.6)
        .padding(12)
        .frame(maxHeight: .infinity)
    }

    private enum ControlsInset { case stacked, side, halfFolded }

    private func controls(_ pos: SunPosition, _ isDark: Bool, inset: ControlsInset) -> some View {
        let onPanel = textColor(isDark), muted = textMuted(isDark)
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(formatBigTime(minutes))
                        .font(.system(size: 24, weight: .bold)).tracking(-0.5)
                        .foregroundStyle(onPanel).monospacedDigit()
                    Text(dateStr).font(.system(size: 12)).foregroundStyle(muted)
                }
                Spacer()
                Button { showDatePicker = true } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(textColor(isDark))
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isDark ? Color(hex: 0xFF1E2126) : Color(hex: 0xFFE6E8EB)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDark ? Color(hex: 0xFF3A3F47) : Color(hex: 0xFFCBCFD4)))
                }
                .buttonStyle(.plain)
                PlayButton(playing: playing, action: togglePlaying).padding(.leading, 8)
            }
            Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0.rounded()) }), in: 0...1439)
                .tint(AppTabBarStyle.accent)
                // Time runs left to right, matching the sun-arc chart, in every language.
                .environment(\.layoutDirection, .leftToRight)
                .padding(.top, 8)
            HStack(spacing: 0) {
                StatTile(icon: "sun.max", label: "ALTITUDE", value: String(format: "%.1f°", pos.altitude),
                         textColor: onPanel, textMuted: muted, accent: 0xFFFFB74D)
                StatTile(icon: "safari", label: "AZIMUTH", value: String(format: "%.0f°", pos.azimuth),
                         textColor: onPanel, textMuted: muted, accent: 0xFF3B7CFF)
                StatTile(icon: "bolt", label: "IRRADIANCE", value: "\(Int(solarIrradianceWm2(pos.altitude).rounded())) W/m²",
                         textColor: onPanel, textMuted: muted, accent: 0xFFFFCA28)
            }
            .padding(.top, 2)
            HStack(spacing: 0) {
                StatTile(icon: "sunrise", label: "SUNRISE", value: formatHHmm(sunTimes.sunrise),
                         textColor: onPanel, textMuted: muted, accent: 0xFFFFB74D)
                StatTile(icon: "moon.stars", label: "SUNSET", value: formatHHmm(sunTimes.sunset),
                         textColor: onPanel, textMuted: muted, accent: 0xFF8B93FF)
                // Evening golden hour start: the one photographers plan around.
                StatTile(icon: "camera.aperture", label: "GOLDEN HOUR", value: formatHHmm(goldenHours.eveningStart),
                         textColor: onPanel, textMuted: muted, accent: 0xFFFFB300)
            }
            .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 14, trailing: 20))
        .glass(radius: kCardRadius, tint: isDark ? Color(hex: 0xFF15171C) : .white, opacity: 0.6)
        .padding(inset == .halfFolded ? EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
                 : inset == .side ? EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 12)
                 : EdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 12))
    }

    private var datePickerSheet: some View {
        let (y, m, d) = dateParts(dateStr)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
        return NavigationStack {
            DatePicker("Date", selection: Binding(get: { date }, set: { picked in
                let c = utc.dateComponents([.year, .month, .day], from: picked)
                dateStr = "\(c.year!)-\(pad2(c.month!))-\(pad2(c.day!))"
            }), in: utc.date(from: DateComponents(year: 1970, month: 1, day: 1))!...utc.date(from: DateComponents(year: 2100, month: 12, day: 31))!,
            displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.timeZone, utc.timeZone)
                .padding()
                .toolbar { Button("Done") { showDatePicker = false } }
        }
        .presentationDetents([.medium, .large])
    }

    /// Lays `first` and `second` out on either side of the fold, leaving the
    /// fold's own band empty: side by side for a vertical fold (book pose),
    /// top and bottom for a horizontal one (laptop pose).
    private func splitAtFold<A: View, B: View>(size: CGSize, first: A, second: B) -> some View {
        let band: CGRect
        if let r = foldRect, !r.isEmpty {
            band = r
        } else {
            // Division not reported yet: assume iPhone Duo's 40pt fold
            // across the middle of the window.
            let foldWidth: CGFloat = 40
            band = windowSize.width > windowSize.height
                ? CGRect(x: size.width / 2 - foldWidth / 2, y: 0, width: foldWidth, height: size.height)
                : CGRect(x: 0, y: size.height / 2 - foldWidth / 2, width: size.width, height: foldWidth)
        }
        // The fold rect is in physical (left-origin) coordinates, so lay the
        // halves out left to right, then give each half the real direction.
        let direction = layoutDirection
        return Group {
            if band.height >= band.width {
                HStack(spacing: 0) {
                    first.environment(\.layoutDirection, direction)
                        .frame(width: clampD(band.minX, 0, size.width))
                    Color.clear.frame(width: band.width)
                    second.environment(\.layoutDirection, direction)
                        .frame(maxWidth: .infinity)
                }
                .environment(\.layoutDirection, .leftToRight)
            } else {
                VStack(spacing: 0) {
                    first.frame(height: clampD(band.minY, 0, size.height))
                    Color.clear.frame(height: band.height)
                    second.frame(maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Logic

    private func recomputeDayPath() {
        let dayStart = localMidnightMs(currentInstantMs, offsetHours: utcOffsetHours)
        let key = "\(dayStart)@\(String(format: "%.2f,%.2f", lat, lng))"
        guard key != lastPathKey else { return }
        lastPathKey = key
        dayAltitudes = stride(from: 0, through: 1440, by: stepMinutes).map {
            sunPosition(instantMs: Double(dayStart + $0 * 60_000), lat: lat, lon: lng).altitude
        }
        sunTimes = findSunriseSunset(dayStartMs: dayStart, lat: lat, lon: lng)
        goldenHours = findGoldenHours(dayStartMs: dayStart, lat: lat, lon: lng)
    }

    private func setLocation(lat: Double, lng: Double, label: String) {
        let offset = approxUtcOffsetHours(lng)
        let f = localFieldsFromInstant(nowMs(), offsetHours: offset)
        self.lat = lat
        self.lng = lng
        utcOffsetHours = offset
        dateStr = dateString(from: f)
        minutes = f.minutesOfDay
        locationLabel = label
        search.selected(label)
        recomputeDayPath()
    }

    private func detectDeviceLocation() {
        Task {
            guard let loc = try? await DeviceLocation.shared.current() else { return }
            setLocation(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, label: String(localized: "My Location", bundle: AppLanguage.bundle))
            if let label = await reverseGeocodeLabel(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude) {
                locationLabel = label
                search.selected(label)
            }
        }
    }

    private func select(_ place: Place) {
        setLocation(lat: place.lat, lng: place.lon, label: place.shortLabel)
    }

    private func togglePlaying() {
        playing.toggle()
        if playing {
            playTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                MainActor.assumeIsolated { minutes = (minutes + 5) % 1440 }
            }
        } else {
            playTimer?.invalidate()
            playTimer = nil
        }
    }
}

/// The day's sun arc: altitude over the day as one golden dome from sunrise
/// to sunset, with the scrubbed time as a glowing dot.
private struct SunArc: View {
    let altitudes: [Double]
    let nowMinutes: Int
    let sunPos: SunPosition
    let sunTimes: SunTimes
    let labelColor: Color
    let isDark: Bool

    private let minAltitude = -16.0

    var body: some View {
        Canvas { ctx, size in
            guard !altitudes.isEmpty else { return }
            let maxAltitude = max(10, altitudes.max() ?? 10) + 12
            func x(_ m: Int) -> CGFloat { size.width * CGFloat(m) / 1440 }
            func y(_ alt: Double) -> CGFloat {
                size.height * CGFloat(1 - clampD((alt - minAltitude) / (maxAltitude - minAltitude), 0, 1))
            }
            let horizonY = y(0)
            let below = sunPos.altitude <= 0.5

            let skyTop = isDark ? Color(hex: below ? 0xFF11131A : 0xFF1B2540) : Color(hex: below ? 0xFFD8DEE8 : 0xFFBFE0FF)
            let skyHorizon = isDark ? Color(hex: below ? 0xFF232A3D : 0xFF3A2E45) : Color(hex: below ? 0xFFEDEFF3 : 0xFFFFE3C2)
            let full = CGRect(origin: .zero, size: size)
            ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [skyTop, skyHorizon]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.fill(Path(CGRect(x: 0, y: horizonY, width: size.width, height: size.height - horizonY)),
                     with: .color(isDark ? Color(hex: 0xFF0C0E12) : Color(hex: 0xFFCED3D9)))

            // Hour ticks every 6 hours along the horizon.
            for m in stride(from: 0, through: 1440, by: 360) {
                var tick = Path()
                tick.move(to: CGPoint(x: x(m), y: horizonY - 3))
                tick.addLine(to: CGPoint(x: x(m), y: horizonY + 3))
                ctx.stroke(tick, with: .color(labelColor.opacity(0.3)))
                let label = formatArcHour(m)
                ctx.draw(Text(label).font(.system(size: 9.5)).foregroundStyle(labelColor.opacity(0.75)),
                         at: CGPoint(x: x(m), y: min(horizonY + 8, size.height - 12)), anchor: .top)
            }

            // Contiguous above/below-horizon runs, each one stroke.
            var dayRuns: [[CGPoint]] = [], nightRuns: [[CGPoint]] = []
            var cur: [CGPoint] = []
            var curIsDay: Bool?
            for m in stride(from: 0, through: 1440, by: stepMinutes) {
                let alt = altitudes[min(m / stepMinutes, altitudes.count - 1)]
                let isDay = alt >= 0
                if curIsDay != nil && curIsDay != isDay {
                    if curIsDay! { dayRuns.append(cur) } else { nightRuns.append(cur) }
                    cur = []
                }
                curIsDay = isDay
                cur.append(CGPoint(x: x(m), y: y(alt)))
            }
            if let curIsDay { if curIsDay { dayRuns.append(cur) } else { nightRuns.append(cur) } }

            func line(_ run: [CGPoint]) -> Path {
                var p = Path()
                p.addLines(run)
                return p
            }
            for run in nightRuns where run.count >= 2 {
                ctx.stroke(line(run), with: .color((isDark ? Color.white : .black).opacity(0.16)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            for run in dayRuns where run.count >= 2 {
                let stroke = line(run)
                var fill = stroke
                fill.addLine(to: CGPoint(x: run.last!.x, y: horizonY))
                fill.addLine(to: CGPoint(x: run.first!.x, y: horizonY))
                fill.closeSubpath()
                ctx.fill(fill, with: .linearGradient(
                    Gradient(colors: [Color(hex: 0xFFFFD580).opacity(isDark ? 0.22 : 0.32), Color(hex: 0xFFFFD580).opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: horizonY)))
                ctx.stroke(stroke, with: .linearGradient(
                    Gradient(colors: [Color(hex: 0xFFFFB74D), Color(hex: 0xFFFFE0A3)]),
                    startPoint: CGPoint(x: run.first!.x, y: 0), endPoint: CGPoint(x: run.last!.x, y: 0)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            func edgeMarker(_ minutes: Int?, _ icon: String, _ accent: Color) {
                guard let minutes else { return }
                let c = CGPoint(x: x(minutes), y: horizonY)
                let circle = Path(ellipseIn: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22))
                ctx.fill(circle, with: .color(accent))
                ctx.stroke(circle, with: .color(.white.opacity(0.85)), lineWidth: 1.4)
                ctx.draw(Text(Image(systemName: icon)).font(.system(size: 11)).foregroundStyle(.white), at: c)
                ctx.draw(Text(formatHHmm(minutes)).font(.system(size: 9.5, weight: .bold)).foregroundStyle(labelColor),
                         at: CGPoint(x: c.x, y: horizonY + 15), anchor: .top)
            }
            edgeMarker(sunTimes.sunrise, "sunrise.fill", Color(hex: 0xFFFFB74D))
            edgeMarker(sunTimes.sunset, "moon.stars.fill", Color(hex: 0xFF8B93FF))

            let now = CGPoint(x: x(nowMinutes), y: y(sunPos.altitude))
            let above = sunPos.altitude > 0.5
            var guide = Path()
            guide.move(to: now)
            guide.addLine(to: CGPoint(x: now.x, y: horizonY))
            ctx.stroke(guide, with: .color((above ? Color(hex: 0xFFFFB74D) : labelColor).opacity(0.35)), lineWidth: 1.2)
            if above {
                ctx.fill(Path(ellipseIn: CGRect(x: now.x - 16, y: now.y - 16, width: 32, height: 32)),
                         with: .color(Color(hex: 0xFFFFD580).opacity(0.3)))
            }
            let dot = Path(ellipseIn: CGRect(x: now.x - 8, y: now.y - 8, width: 16, height: 16))
            ctx.fill(dot, with: .color(above ? Color(hex: 0xFFFFD580) : .white.opacity(0.38)))
            ctx.stroke(dot, with: .color(.black.opacity(0.25)), lineWidth: 1.2)
        }
    }
}
