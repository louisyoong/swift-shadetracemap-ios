import SwiftUI

// Shared design tokens and small building blocks, ported from the Flutter
// app's lib/app_style.dart and lib/glass_panel.dart.

extension Color {
    /// Flutter-style 0xAARRGGBB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: Double((hex >> 24) & 0xFF) / 255
        )
    }
}

/// A color that can be interpolated, for the live sky/temperature tints
/// (Flutter's Color.lerp).
struct RGBA: Equatable {
    var r, g, b, a: Double

    init(_ hex: UInt32) {
        a = Double((hex >> 24) & 0xFF) / 255
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    func lerp(_ other: RGBA, _ t: Double) -> RGBA {
        let t = clampD(t, 0, 1)
        return RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t,
                    b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

let kLightText = Color(hex: 0xFF2A2620)
let kLightTextMuted = Color(hex: 0x992A2620)
let kDarkText = Color(hex: 0xFFF3F1EC)
let kDarkTextMuted = Color(hex: 0x99F3F1EC)
let kBlue = Color(hex: 0xFF3B7CFF)
let kGold = Color(hex: 0xFFFFB300)

func textColor(_ isDark: Bool) -> Color { isDark ? kDarkText : kLightText }
func textMuted(_ isDark: Bool) -> Color { isDark ? kDarkTextMuted : kLightTextMuted }

/// Tones a vivid accent down for light backgrounds by blending it toward
/// the light-mode ink color.
func accentForTheme(_ accent: UInt32, _ isDark: Bool) -> Color {
    isDark ? Color(hex: accent) : RGBA(accent).lerp(RGBA(0xFF2A2620), 0.3).color
}

func badgeBackground(_ accent: UInt32, _ isDark: Bool) -> Color {
    isDark ? accentForTheme(accent, isDark).opacity(0.15) : accentForTheme(accent, isDark)
}

func badgeIconColor(_ accent: UInt32, _ isDark: Bool) -> Color {
    isDark ? accentForTheme(accent, isDark) : .white
}

let kCardRadius: CGFloat = 22
let kCompactHeightBreakpoint: CGFloat = 500
let kSidePanelWidth: CGFloat = 340

// MARK: - Window size

private struct WindowSizeKey: EnvironmentKey {
    static let defaultValue = CGSize(width: 390, height: 844)
}

extension EnvironmentValues {
    /// The full window size (Flutter's MediaQuery.size), set once at the root.
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}

/// Short window (iPhone Duo outer display in landscape, phones in landscape).
func isCompactHeight(_ size: CGSize) -> Bool { size.height < kCompactHeightBreakpoint }

/// Landscape-shaped and wide enough for two columns.
func useSideBySideLayout(_ size: CGSize) -> Bool { size.width >= 600 && size.width > size.height }

// MARK: - Glass panel

/// A translucent "frosted glass" panel: system blur material under a tinted,
/// semi-transparent fill. SwiftUI's material is a real UIKit blur, so it
/// renders correctly over the native map too - the Flutter app had to drop
/// its liquid-glass shader because it couldn't see platform views behind it.
struct GlassPanel: ViewModifier {
    var radius: CGFloat = 14
    var circle = false
    var tint: Color = Color(hex: 0xFF15171C)
    var tintOpacity: Double = 0.55

    func body(content: Content) -> some View {
        let shape = circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint.opacity(tintOpacity)))
            }
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: Color(hex: 0x4D000000), radius: 10, y: 6)
    }
}

extension View {
    func glass(radius: CGFloat = 14, circle: Bool = false, tint: Color = Color(hex: 0xFF15171C), opacity: Double = 0.55) -> some View {
        modifier(GlassPanel(radius: radius, circle: circle, tint: tint, tintOpacity: opacity))
    }
}

// MARK: - Building blocks

struct SectionLabel: View {
    let text: LocalizedStringKey
    let color: Color
    var fontSize: CGFloat = 11

    init(_ text: LocalizedStringKey, color: Color, fontSize: CGFloat = 11) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
    }

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

/// A single stat readout - an icon in a soft tinted circular badge, a bold
/// value, and an uppercase label underneath.
struct StatTile: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let label: LocalizedStringKey
    let value: String
    let textColor: Color
    let textMuted: Color
    var accent: UInt32?
    var valueColor: Color?

    var body: some View {
        let isDark = scheme == .dark
        // Without an accent the Flutter tile falls back to the text color.
        let raw = accent ?? (isDark ? 0xFFF3F1EC : 0xFF2A2620)
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(badgeIconColor(raw, isDark))
                .frame(width: 28, height: 28)
                .background(Circle().fill(badgeBackground(raw, isDark)))
            Text(value)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(valueColor ?? textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 7)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A rounded chip showing the current location with a pin icon.
struct LocationChip: View {
    let label: String
    let textColor: Color
    let isDark: Bool
    /// Adds a chevron when the chip opens a menu.
    var showsMenu = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "mappin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor.opacity(0.75))
            Text(label)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
            if showsMenu {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(textColor.opacity(0.6))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill((isDark ? Color.white : Color.black).opacity(0.08)))
    }
}

/// A 30pt round play / pause button, styled like the tab bar's selected item.
struct PlayButton: View {
    @Environment(\.colorScheme) private var scheme
    let playing: Bool
    let action: () -> Void

    var body: some View {
        let style = scheme == .dark ? AppTabBarStyle.dark : AppTabBarStyle.light
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 13))
                .foregroundStyle(style.active)
                .frame(width: 30, height: 30)
                .background(ActiveIndicator(style: style, vertical: true))
        }
        .buttonStyle(.plain)
    }
}

/// Interpolates a two-stop vertical gradient between night, golden-hour and
/// midday-sky tones from the sun's altitude. Shared by Sun Path and Compass.
func sunTint(_ altitude: Double, isDark: Bool) -> (top: RGBA, bottom: RGBA) {
    let nightTop, nightBottom, horizonTop, horizonBottom, zenithTop, zenithBottom: RGBA
    if isDark {
        nightTop = RGBA(0xFF05060B); nightBottom = RGBA(0xFF12141E)
        horizonTop = RGBA(0xFF7A3A1E); horizonBottom = RGBA(0xFF241209)
        zenithTop = RGBA(0xFF17436A); zenithBottom = RGBA(0xFF0B1B2E)
    } else {
        nightTop = RGBA(0xFF54628F); nightBottom = RGBA(0xFFC7CDE4)
        horizonTop = RGBA(0xFFFF9E6D); horizonBottom = RGBA(0xFFFFF1E0)
        zenithTop = RGBA(0xFF6EC1F5); zenithBottom = RGBA(0xFFEAF6FF)
    }
    if altitude <= 8 {
        let t = (altitude + 10) / 18
        return (nightTop.lerp(horizonTop, t), nightBottom.lerp(horizonBottom, t))
    }
    let t = (altitude - 8) / 52
    return (horizonTop.lerp(zenithTop, t), horizonBottom.lerp(zenithBottom, t))
}

/// 0→1→0 ping-pong over `period` seconds, like a Flutter
/// AnimationController with repeat(reverse: true).
func pingPong(_ date: Date, period: Double) -> Double {
    let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period * 2) / period
    return t <= 1 ? t : 2 - t
}
