import SwiftUI
import CoreLocation
import Combine

/// Device heading from Core Location (what flutter_compass wraps).
@MainActor
@Observable
final class HeadingProvider: NSObject, CLLocationManagerDelegate {
    private(set) var heading: Double?
    private(set) var unavailable = false
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        guard CLLocationManager.headingAvailable() else {
            unavailable = true
            return
        }
        started = true
        manager.delegate = self
        // Same fine-grained updates as flutter_compass, so the dial turns smoothly.
        manager.headingFilter = 0.1
        // Report heading relative to the top of the screen as currently held,
        // so it stays right in landscape (e.g. the iPhone Duo inner display).
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHeadingOrientation() }
        }
        updateHeadingOrientation()
        manager.startUpdatingHeading()
        // A real magnetometer reports almost immediately; a simulator never
        // will, so fall back to a labelled note.
        Task {
            try? await Task.sleep(for: .seconds(3))
            if heading == nil { unavailable = true }
        }
    }

    /// Only portrait and the two landscapes change which way "forward" is;
    /// flat (face up/down) and unknown keep the last upright orientation.
    private func updateHeadingOrientation() {
        switch UIDevice.current.orientation {
        case .portrait: manager.headingOrientation = .portrait
        case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
        case .landscapeLeft: manager.headingOrientation = .landscapeLeft
        case .landscapeRight: manager.headingOrientation = .landscapeRight
        default: break
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            heading = h
            unavailable = false
        }
    }

    /// Lets iOS show its figure-8 calibration prompt when the magnetometer is
    /// badly off (accuracy worse than ±25°, or invalid), instead of quietly
    /// pointing the wrong way.
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        guard let accuracy = manager.heading?.headingAccuracy else { return true }
        return accuracy < 0 || accuracy > 25
    }
}

/// A live sun-finding compass: the sun marker slides around the dial to
/// point at its real-world direction as the phone turns.
struct CompassScreen: View {
    @Environment(\.windowSize) private var windowSize
    @Environment(\.colorScheme) private var scheme

    @State private var lat = 3.1412
    @State private var lng = 101.68653
    @State private var locationLabel = String(localized: "Kuala Lumpur, Malaysia", bundle: AppLanguage.bundle)
    @State private var compass = HeadingProvider()
    @State private var now = Date()
    @State private var wasFacingSun = false
    @State private var facingT = 0.0

    private let clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        let isDark = scheme == .dark
        let pos = sunPosition(now, lat: lat, lon: lng)
        let aboveHorizon = pos.altitude > 0.5
        let sideBySide = useSideBySideLayout(windowSize)

        TimelineView(.animation) { timeline in
            let sweepT = pingPong(timeline.date, period: 10)
            let pulseT = pingPong(timeline.date, period: 3)
            ZStack {
                background(pos.altitude, isDark: isDark, sweepT: sweepT, pulseT: pulseT)
                    .ignoresSafeArea()
                if sideBySide {
                    HStack(spacing: 0) {
                        VStack(spacing: 12) {
                            chip(isDark)
                            dial(pos, aboveHorizon, isDark, pulseT: pulseT)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        ScrollView {
                            VStack(spacing: 12) {
                                facingLine(pos, aboveHorizon, isDark)
                                readouts(pos, isDark).padding(.trailing, 12).padding(.bottom, 12)
                            }
                            .padding(.top, 12)
                        }
                        .defaultScrollAnchor(.center)
                        .frame(width: kSidePanelWidth)
                    }
                } else {
                    VStack(spacing: 0) {
                        chip(isDark)
                        dial(pos, aboveHorizon, isDark, pulseT: pulseT, pinnedTop: true)
                        facingLine(pos, aboveHorizon, isDark)
                        readouts(pos, isDark).padding([.horizontal, .bottom], 12).padding(.top, 12)
                    }
                }
            }
        }
        .onAppear {
            compass.start()
            detectDeviceLocation()
        }
        .onReceive(clock) { now = $0; updateFacingEffects() }
        .onChange(of: compass.heading) { updateFacingEffects() }
    }

    // MARK: - Pieces

    /// Sky tint + slow sweep, cross-faded into a breathing warm glow once the
    /// phone faces the sun. The warm layer's opacity is `facingT`, which is
    /// exactly Flutter's Color.lerp(base, warm, facingT) for opaque colors.
    private func background(_ altitude: Double, isDark: Bool, sweepT: Double, pulseT: Double) -> some View {
        let base = sunTint(altitude, isDark: isDark)
        let start = UnitPoint(x: 0.5 - 0.175 * sweepT, y: 0)
        let end = UnitPoint(x: 0.5 + 0.175 * sweepT, y: 1)
        let warmTop = RGBA(0xFFFFC107).lerp(RGBA(0xFFFFECB3), pulseT).color
        let warmBottom = RGBA(0xFFFF6F00).lerp(RGBA(0xFFFFB300), pulseT).color
        return ZStack {
            LinearGradient(colors: [base.top.color, base.bottom.color], startPoint: start, endPoint: end)
            LinearGradient(colors: [warmTop, warmBottom], startPoint: start, endPoint: end).opacity(facingT)
        }
    }

    private func chip(_ isDark: Bool) -> some View {
        LocationChip(label: locationLabel, textColor: textColor(isDark), isDark: isDark)
            .padding(.horizontal, 12)
            .padding(.top, 12)
    }

    /// `pinnedTop` sits the dial just under the location chip instead of
    /// centring it, so tall windows (iPhone Duo inner display) don't leave it
    /// floating in the middle with empty space above.
    private func dial(_ pos: SunPosition, _ above: Bool, _ isDark: Bool, pulseT: Double,
                      pinnedTop: Bool = false) -> some View {
        // Scales the dial down on short windows (landscape, iPhone Duo outer
        // display) instead of overflowing - Flutter's FittedBox(scaleDown).
        GeometryReader { geo in
            let topInset: CGFloat = pinnedTop ? 32 : 0
            let scale = min(1, min(geo.size.width, geo.size.height - topInset) / 300)
            ZStack {
                if facingT > 0 {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: 0xFFFFD54F).opacity(0.45), Color(hex: 0xFFFFD54F).opacity(0)],
                                             center: .center, startRadius: 0, endRadius: (300 + 50 * pulseT) / 2))
                        .frame(width: 300 + 50 * pulseT, height: 300 + 50 * pulseT)
                        .opacity(facingT)
                }
                CompassDial(heading: compass.heading, sunAzimuth: pos.azimuth, sunAboveHorizon: above, isDark: isDark)
                    .frame(width: 288, height: 288)
            }
            .frame(width: 288, height: 288)
            .scaleEffect(scale, anchor: pinnedTop ? .top : .center)
            .padding(.top, topInset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: pinnedTop ? .top : .center)
        }
    }

    private func facingInfo(_ pos: SunPosition) -> (diff: Double, facing: Bool) {
        guard pos.altitude > 0.5, let heading = compass.heading else { return (0, false) }
        let diff = (norm360(pos.azimuth - heading) + 180).truncatingRemainder(dividingBy: 360) - 180
        return (diff, abs(diff) <= 12)
    }

    private func facingLine(_ pos: SunPosition, _ above: Bool, _ isDark: Bool) -> some View {
        let message: String
        if !above {
            message = String(localized: "Sun is below the horizon right now.", bundle: AppLanguage.bundle)
        } else if compass.heading == nil {
            message = String(localized: "Sun is at \(Int(pos.azimuth.rounded()))° from true north.", bundle: AppLanguage.bundle)
        } else {
            let info = facingInfo(pos)
            message = info.facing ? String(localized: "You're facing the sun.", bundle: AppLanguage.bundle)
                : info.diff > 0
                    ? String(localized: "Turn right \(Int(abs(info.diff).rounded()))° to face the sun.", bundle: AppLanguage.bundle)
                    : String(localized: "Turn left \(Int(abs(info.diff).rounded()))° to face the sun.", bundle: AppLanguage.bundle)
        }
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                if above && compass.heading != nil {
                    Image(systemName: facingInfo(pos).facing ? "checkmark.circle.fill" : "location.north.fill")
                        .font(.system(size: 14))
                }
                Text(message).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center)
            }
            .foregroundStyle(textColor(isDark))
            if compass.unavailable {
                Text("No live compass sensor detected (simulators don't have one) - showing the sun's bearing from true north instead.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(textMuted(isDark))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
    }

    private func readouts(_ pos: SunPosition, _ isDark: Bool) -> some View {
        let tc = textColor(isDark), tm = textMuted(isDark)
        let dayStart = localMidnightMs(Int(now.timeIntervalSince1970 * 1000), offsetHours: approxUtcOffsetHours(lng))
        let times = findSunriseSunset(dayStartMs: dayStart, lat: lat, lon: lng)
        return HStack(spacing: 0) {
            StatTile(icon: "sun.max", label: "ALTITUDE", value: String(format: "%.1f°", pos.altitude),
                     textColor: tc, textMuted: tm, accent: 0xFFFFB74D)
            StatTile(icon: "safari", label: "SUN AZIMUTH", value: String(format: "%.0f°", pos.azimuth),
                     textColor: tc, textMuted: tm, accent: 0xFF3B7CFF)
            StatTile(icon: "location.north", label: "HEADING", value: compass.heading.map { String(format: "%.0f°", $0) } ?? "--°",
                     textColor: tc, textMuted: tm, accent: 0xFF7E57C2)
            StatTile(icon: "moon.stars", label: "SUNSET", value: formatHHmm(times.sunset),
                     textColor: tc, textMuted: tm, accent: 0xFF8B93FF)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .glass(radius: kCardRadius, tint: isDark ? Color(hex: 0xFF15171C) : .white, opacity: isDark ? 0.55 : 0.4)
    }

    // MARK: - Logic

    /// Buzz once on the moment the phone swings into alignment, and fade the
    /// warm glow in or out.
    private func updateFacingEffects() {
        let facing = facingInfo(sunPosition(Date(), lat: lat, lon: lng)).facing
        if facing && !wasFacingSun {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        withAnimation(.linear(duration: 0.45)) { facingT = facing ? 1 : 0 }
        wasFacingSun = facing
    }

    private func detectDeviceLocation() {
        Task {
            guard let loc = try? await DeviceLocation.shared.current() else { return }
            lat = loc.coordinate.latitude
            lng = loc.coordinate.longitude
            locationLabel = String(localized: "My Location", bundle: AppLanguage.bundle)
            updateFacingEffects()
            if let label = await reverseGeocodeLabel(lat: lat, lon: lng) { locationLabel = label }
        }
    }
}

private struct CompassDial: View {
    let heading: Double?
    let sunAzimuth: Double
    let sunAboveHorizon: Bool
    let isDark: Bool

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = size.width / 2
            let h = heading ?? 0
            let ring = Path(ellipseIn: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            ctx.fill(ring, with: .color(isDark ? Color(hex: 0xFF15171C).opacity(0.5) : .white.opacity(0.55)))
            ctx.stroke(ring, with: .color(isDark ? .white.opacity(0.16) : .black.opacity(0.12)), lineWidth: 2)

            // North at the top, rotating with -heading.
            func point(_ bearing: Double, _ radius: CGFloat) -> CGPoint {
                let a = toRad(bearing - h - 90)
                return CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
            }
            for b in stride(from: 0.0, to: 360, by: 30) {
                var tick = Path()
                tick.move(to: point(b, r - 14))
                tick.addLine(to: point(b, r - 4))
                ctx.stroke(tick, with: .color(isDark ? .white.opacity(0.35) : .black.opacity(0.28)), lineWidth: 2)
            }
            let north = isDark ? Color(hex: 0xFFFF8A7A) : Color(hex: 0xFFE04B36)
            let label = isDark ? Color(hex: 0xFFDFE3E8) : Color(hex: 0xFF52575E)
            let cardinals: [(Double, LocalizedStringKey)] = [(0, "N"), (90, "E"), (180, "S"), (270, "W")]
            for (b, s) in cardinals {
                ctx.draw(Text(s).font(.system(size: 15, weight: .bold)).foregroundStyle(b == 0 ? north : label),
                         at: point(b, r - 30))
            }

            // Fixed pointer = where the phone faces.
            let pointerColor = isDark ? Color(hex: 0xFF6FB2FF) : Color(hex: 0xFF3B7CFF)
            var pointer = Path()
            pointer.move(to: CGPoint(x: c.x, y: c.y - r - 14))
            pointer.addLine(to: CGPoint(x: c.x - 8, y: c.y - r + 4))
            pointer.addLine(to: CGPoint(x: c.x + 8, y: c.y - r + 4))
            pointer.closeSubpath()
            ctx.fill(pointer, with: .color(pointerColor))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(pointerColor))

            // Sun/moon marker at its real-world bearing.
            let sun = point(sunAzimuth, r * 0.62)
            let accent = sunAboveHorizon ? Color(hex: 0xFFFFB74D) : Color(hex: 0xFF7C93FF)
            var spoke = Path()
            spoke.move(to: c)
            spoke.addLine(to: sun)
            ctx.stroke(spoke, with: .color(accent.opacity(0.35)), lineWidth: 2)
            var glow = ctx
            glow.addFilter(.blur(radius: 8))
            glow.fill(Path(ellipseIn: CGRect(x: sun.x - 20, y: sun.y - 20, width: 40, height: 40)), with: .color(accent.opacity(0.35)))
            let disc = Path(ellipseIn: CGRect(x: sun.x - 14, y: sun.y - 14, width: 28, height: 28))
            ctx.fill(disc, with: .color(.white))
            ctx.stroke(disc, with: .color(accent), lineWidth: 2)
            ctx.draw(Text(Image(systemName: sunAboveHorizon ? "sun.max.fill" : "moon.fill"))
                        .font(.system(size: 14)).foregroundStyle(accent), at: sun)
        }
    }
}
