import SwiftUI

/// Port of the Flutter app's AppTabBar (lib/app_tab_bar.dart) with the exact
/// colors from root_shell.dart's _lightTabBarStyle / _darkTabBarStyle: a
/// frosted glass pill, amber active item, grey inactive items, and a sliding
/// amber-tinted indicator you can also drag between tabs.
///
/// The native iOS 26+ tab bar ignores custom item/indicator colors, which is
/// why this is hand-built for the bottom bar.
struct TabBarItem: Identifiable {
    let id: Int
    let icon: String
    let label: String
}

struct AppTabBarStyle {
    let active: Color
    let inactive: Color
    let indicatorGradient: [Color]
    let indicatorBorder: Color
    let indicatorGlow: Color
    let outerBorder: Color
    let outerBorderWidth: CGFloat
    let glassTint: Color
    let glassTintOpacity: Double

    static let accent = Color(hex: 0xFFFFB300)

    static let light = AppTabBarStyle(
        active: accent,
        inactive: Color(hex: 0xFF6B7078),
        indicatorGradient: [Color(hex: 0x2EFFB300), Color(hex: 0x8CFFFFFF), Color(hex: 0x40FFFFFF)],
        indicatorBorder: Color(hex: 0xB3FFFFFF),
        indicatorGlow: Color(hex: 0xCCFFFFFF),
        outerBorder: Color(hex: 0xD9FFFFFF),
        outerBorderWidth: 1.5,
        glassTint: .white,
        glassTintOpacity: 0.7
    )

    /// The light-mode tab bar itself: light grey glass with black items, like
    /// the system status pill on iPhone Duo, and an amber active item a shade
    /// darker than the dark bar's so it holds up on the light glass.
    /// Other controls that borrow the active look keep using `light`.
    static let lightBar = AppTabBarStyle(
        active: Color(hex: 0xFFE68900),
        inactive: .black,
        indicatorGradient: [Color(hex: 0x80FFC107), Color(hex: 0x4DFFC107), Color(hex: 0x1AFFFFFF)],
        indicatorBorder: Color(hex: 0xB3E68900),
        indicatorGlow: Color(hex: 0x24FFFFFF),
        outerBorder: Color(hex: 0x66FFFFFF),
        outerBorderWidth: 1.2,
        glassTint: Color(hex: 0xFFE4E4E7),
        glassTintOpacity: 0.6
    )

    static let dark = AppTabBarStyle(
        active: accent,
        inactive: Color(hex: 0xFF9AA0A8),
        indicatorGradient: [Color(hex: 0x59FFB300), Color(hex: 0x2EFFB300), Color(hex: 0x0FFFFFFF)],
        indicatorBorder: Color(hex: 0x73FFB300),
        indicatorGlow: Color(hex: 0x24FFFFFF),
        outerBorder: Color(hex: 0x1AFFFFFF),
        outerBorderWidth: 1.2,
        glassTint: Color(hex: 0xFF171F38),
        glassTintOpacity: 0.55
    )
}

struct AppTabBar: View {
    @Environment(\.colorScheme) private var scheme
    let items: [TabBarItem]
    let selected: Int
    /// Short windows: slimmer bar, icons only.
    let compact: Bool
    /// iPhone Duo side column: a slim icon-only bar laid out top to bottom
    /// with a round indicator, like the Flutter app's Axis.vertical bar.
    var vertical = false
    let onSelect: (Int) -> Void

    @State private var dragOffset: CGFloat?
    @State private var dragStart: CGFloat = 0

    private let radius: CGFloat = 28
    /// Bar thickness: height when horizontal, width when vertical.
    private var thickness: CGFloat { vertical ? 44 : (compact ? 42 : 54) }

    static func totalHeight(compact: Bool) -> CGFloat {
        // bar + 6pt inner padding each side + vertical outer padding
        (compact ? 42 : 54) + 12 + (compact ? 6 : 10) * 2
    }

    /// Width of the vertical bar including its glass padding.
    static let verticalWidth: CGFloat = 44 + 12
    /// Extra length per slot in the vertical bar, so the round indicators
    /// don't touch (Flutter's _verticalSlotGap).
    private static let verticalSlotGap: CGFloat = 8

    var body: some View {
        let style = scheme == .dark ? AppTabBarStyle.dark : AppTabBarStyle.lightBar
        let count = CGFloat(items.count)
        GeometryReader { geo in
            let length = vertical ? geo.size.height : geo.size.width
            let slot = length / count
            let rest = CGFloat(selected) * slot
            let pos = dragOffset ?? rest
            let highlighted = dragOffset.map { Int(($0 / slot).rounded()) }

            ZStack(alignment: vertical ? .top : .leading) {
                indicator(style)
                    .frame(width: vertical ? thickness - 2 : slot, height: vertical ? thickness - 2 : thickness - 4)
                    .frame(width: vertical ? thickness : slot, height: vertical ? slot : thickness)
                    .offset(x: vertical ? 0 : pos, y: vertical ? pos : 0)
                    .animation(dragOffset == nil ? .easeOut(duration: 0.25) : nil, value: pos)

                let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                layout {
                    ForEach(items) { item in
                        itemView(item, style: style, highlighted: highlighted)
                            .frame(width: vertical ? thickness : slot, height: vertical ? slot : thickness)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(item.id) }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: selected)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        if dragOffset == nil { dragStart = rest }
                        let delta = vertical ? v.translation.height : v.translation.width
                        dragOffset = clampD(Double(dragStart + delta), 0, Double(length - slot))
                    }
                    .onEnded { _ in
                        if let d = dragOffset {
                            onSelect(min(items.count - 1, max(0, Int((d / slot).rounded()))))
                        }
                        dragOffset = nil
                    }
            )
        }
        .frame(width: vertical ? thickness : nil,
               height: vertical ? count * (thickness + Self.verticalSlotGap) : thickness)
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(style.glassTint.opacity(style.glassTintOpacity)))
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(style.outerBorder, lineWidth: style.outerBorderWidth))
        .shadow(color: Color(hex: 0x4D000000), radius: 10, y: vertical ? 0 : 6)
        .frame(maxWidth: vertical ? nil : 560)
        .padding(.horizontal, vertical ? 0 : 16)
        .padding(.vertical, vertical ? 0 : (compact ? 6 : 10))
        // The indicator is placed with offsets from the leading edge, so keep
        // one fixed direction (tab order stays the same in Arabic).
        .environment(\.layoutDirection, .leftToRight)
    }

    private func indicator(_ style: AppTabBarStyle) -> some View {
        ActiveIndicator(style: style, vertical: vertical)
    }

    private func itemView(_ item: TabBarItem, style: AppTabBarStyle, highlighted: Int?) -> some View {
        let isSelected = item.id == selected
        let isActive = isSelected || highlighted == item.id
        return VStack(spacing: 2) {
            Image(systemName: item.icon)
                .font(.system(size: vertical ? 19 : 21))
                // Same box for every glyph so labels line up.
                .frame(width: 28, height: 24)
                .scaleEffect(isSelected ? 1.15 : 1)
                .animation(.spring(response: 0.4, dampingFraction: 0.45), value: isSelected)
            if !isSelected && !compact && !vertical {
                Text(item.label)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(isActive ? style.active : style.inactive)
        .animation(.easeOut(duration: 0.25), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The selected tab's amber bubble. Shared so other controls (the iPhone Duo
/// map toolbar toggle) can read as "active" in exactly the same way.
struct ActiveIndicator: View {
    let style: AppTabBarStyle
    var vertical = false

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(LinearGradient(stops: [
                .init(color: style.indicatorGradient[0], location: 0),
                .init(color: style.indicatorGradient[1], location: 0.4),
                .init(color: style.indicatorGradient[2], location: 1),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(style.indicatorBorder, lineWidth: 1.5))
            // Off-axis shadows make the round indicator look off-center in
            // the slim vertical bar.
            .shadow(color: style.active.opacity(0.25), radius: 6, y: vertical ? 0 : 4)
            .shadow(color: style.indicatorGlow, radius: 4, x: vertical ? 0 : -2, y: vertical ? 0 : -2)
    }
}
