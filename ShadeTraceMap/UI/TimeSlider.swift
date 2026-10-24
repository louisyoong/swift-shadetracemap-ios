import SwiftUI

/// Builds the day/night/twilight gradient for the time slider's track. The
/// window (start/span, minutes of day) lets the track show a zoomed-in slice
/// of the day; the dawn/dusk bands keep a fixed width in minutes.
func dayGradientStops(sunrise: Int?, sunset: Int?, isDark: Bool,
                      windowStart: Double = 0, windowSpan: Double = 1440) -> [Gradient.Stop] {
    let sr = Double(sunrise ?? Int((0.29 * 1440).rounded()))
    let ss = Double(sunset ?? Int((0.81 * 1440).rounded()))
    let night = Color(hex: 0xFF171F38)
    let dawnDusk1 = Color(hex: 0xFFFFCF94)
    let day = isDark ? Color(hex: 0xFFBFE4FF) : Color(hex: 0xFF3D7FC4)
    let dawnDusk2 = Color(hex: 0xFFFFB877)
    let softNear = 0.02 * 1440, softFar = 0.06 * 1440
    func frac(_ m: Double) -> Double { clampD((m - windowStart) / windowSpan, 0, 1) }
    var locs = [0, frac(sr - softNear), frac(sr), frac(sr + softFar),
                frac(ss - softFar), frac(ss), frac(ss + softNear), 1]
    for i in 1..<locs.count where locs[i] < locs[i - 1] { locs[i] = locs[i - 1] }
    let colors = [night, night, dawnDusk1, day, day, dawnDusk2, night, night]
    return zip(colors, locs).map { Gradient.Stop(color: $0, location: $1) }
}

/// The time-of-day slider: one-finger drag scrubs the minute, a two-finger
/// pinch zooms the visible window down to one hour for finer scrubbing, and
/// double-tap (or the badge) resets the zoom.
struct TimeSlider: View {
    let minutes: Int
    let sunrise: Int?
    let sunset: Int?
    let isDark: Bool
    let onChange: (Int) -> Void

    private let minSpan = 60.0
    private let maxSpan = 1440.0
    private let inset: CGFloat = 18

    @State private var span = 1440.0
    @State private var center = 720.0
    @State private var pinchBase: (span: Double, center: Double, focal: CGFloat)?
    @State private var dragBase: (minutes: Double, x: CGFloat)?

    private var start: Double { clampD(center - span / 2, 0, maxSpan - span) }
    private var zoomed: Bool { span < maxSpan - 1 }

    var body: some View {
        let isDay = sunrise.map { minutes >= $0 } == true && sunset.map { minutes < $0 } == true
        let muted = isDark ? Color(hex: 0xFF9AA0A8) : Color(hex: 0xFF6B7078)

        GeometryReader { geo in
            let width = geo.size.width
            let xFor: (Double) -> CGFloat = { mins in
                inset + CGFloat(clampD((mins - start) / span, 0, 1)) * (width - inset * 2)
            }
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    Color.clear
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(stops: dayGradientStops(sunrise: sunrise, sunset: sunset, isDark: isDark,
                                                                     windowStart: start, windowSpan: span),
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke((isDark ? Color.white : Color.black).opacity(0.08), lineWidth: 1))
                        .shadow(color: .black.opacity(isDark ? 0.35 : 0.12), radius: 2.5, y: 2)
                        .frame(width: max(0, width - inset * 2), height: 18)
                        .offset(x: inset, y: 13)
                    if let sr = sunrise, Double(sr) >= start, Double(sr) <= start + span {
                        SunMarker(icon: "sunrise.fill").offset(x: xFor(Double(sr)) - 7, y: 15)
                    }
                    if let ss = sunset, Double(ss) >= start, Double(ss) <= start + span {
                        SunMarker(icon: "moon.stars.fill").offset(x: xFor(Double(ss)) - 7, y: 15)
                    }
                    TimeThumb(isDay: isDay).offset(x: xFor(Double(minutes)) - 13, y: 9)
                    if zoomed {
                        ZoomBadge(span: span)
                            .onTapGesture(perform: resetZoom)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width).simultaneously(with: pinchGesture(width: width)))
                .simultaneousGesture(TapGesture(count: 2).onEnded { if zoomed { resetZoom() } })

                HourLabels(start: start, span: span, xFor: xFor, color: muted)
                    .frame(height: 12)
            }
        }
        .frame(height: 60)
        // A time axis runs left to right even in Arabic.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                // While pinching, the drag stream is ignored; when the second
                // finger lifts, re-anchor so the value doesn't jump.
                guard pinchBase == nil else { dragBase = nil; return }
                if dragBase == nil { dragBase = (Double(minutes), v.location.x) }
                guard let base = dragBase else { return }
                let dMinutes = Double(v.location.x - base.x) / Double(width) * span
                onChange(Int(clampD((base.minutes + dMinutes).rounded(), 0, 1439)))
            }
            .onEnded { _ in dragBase = nil }
    }

    private func pinchGesture(width: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchBase == nil { pinchBase = (span, center, v.startLocation.x) }
                guard let base = pinchBase else { return }
                let newSpan = clampD(base.span / v.magnification, minSpan, maxSpan)
                // Keep the minute under the pinch midpoint still on screen.
                let focalFrac = clampD(Double(base.focal / width), 0, 1)
                let anchor = base.center - base.span / 2 + focalFrac * base.span
                span = newSpan
                center = clampD(anchor - (focalFrac - 0.5) * newSpan, newSpan / 2, maxSpan - newSpan / 2)
            }
            .onEnded { _ in pinchBase = nil }
    }

    private func resetZoom() {
        span = maxSpan
        center = 720
    }
}

private struct SunMarker: View {
    let icon: String
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 7))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(Circle().fill(Color(hex: 0xFF1B1D22).opacity(0.75)))
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
            .allowsHitTesting(false)
    }
}

/// White knob with a sun/moon glyph and a warm (day) or cool (night) glow.
private struct TimeThumb: View {
    let isDay: Bool
    var body: some View {
        let accent = isDay ? Color(hex: 0xFFFFB74D) : Color(hex: 0xFF7C93FF)
        ZStack {
            Circle().fill(accent.opacity(0.35)).frame(width: 38, height: 38).blur(radius: 6)
            Circle().fill(.white).frame(width: 26, height: 26)
            Circle().stroke(accent, lineWidth: 2).frame(width: 26, height: 26)
            Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 12))
                .foregroundStyle(accent)
        }
        .frame(width: 26, height: 26)
        .allowsHitTesting(false)
    }
}

private struct ZoomBadge: View {
    let span: Double
    var body: some View {
        let label = span < 90 ? "\(Int(span.rounded()))m"
            : String(format: span.truncatingRemainder(dividingBy: 60) == 0 ? "%.0fh" : "%.1fh", span / 60)
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .semibold))
            Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.55)))
        .padding(.top, 2)
        .padding(.trailing, 2)
    }
}

/// Hour/minute tick labels whose interval adapts to the zoom level.
private struct HourLabels: View {
    let start: Double
    let span: Double
    let xFor: (Double) -> CGFloat
    let color: Color

    private var step: Int {
        for s in [360, 180, 120, 60, 30, 15, 10, 5] where span / Double(s) >= 3.5 { return s }
        return 5
    }

    var body: some View {
        let first = Int((start / Double(step)).rounded(.up)) * step
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(stride(from: first, through: Int(start + span), by: step)), id: \.self) { m in
                Text(formatTickTime(m))
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 44)
                    .offset(x: xFor(Double(m)) - 22)
            }
        }
    }
}
