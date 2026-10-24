import SwiftUI
import MapLibre

private let lightPanelTint = Color(hex: 0xFFE9EBEE)
private let workspacePanelWidth: CGFloat = 340
private let legendWidth: CGFloat = 250

/// The native MapLibre map, wrapped for SwiftUI. Created once and kept alive
/// by the TabView, so switching layouts never rebuilds it.
private struct MapLibreView: UIViewRepresentable {
    let model: ShadeMapModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = model.makeMapView()
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject, MLNMapViewDelegate {
        let model: ShadeMapModel
        init(model: ShadeMapModel) { self.model = model }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated { model.onStyleLoaded(style) }
        }

        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            MainActor.assumeIsolated { model.onCameraMoving() }
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            MainActor.assumeIsolated {
                model.onCameraMoving()
                model.scheduleRecompute()
            }
        }
    }
}

struct ShadeMapScreen: View {
    @Environment(FoldState.self) private var fold
    @Environment(\.windowSize) private var windowSize
    @Environment(\.colorScheme) private var scheme
    @State private var model = ShadeMapModel()

    /// Unfolded iPhone Duo: a map workspace with a docked side panel. Needs
    /// room for the panel plus a useful amount of map beside it.
    private var workspace: Bool { fold.posture == .unfolded && windowSize.width >= 700 }

    var body: some View {
        ZStack {
            // The map stays the first child in every layout, so switching
            // between phone and workspace chrome never rebuilds it.
            MapLibreView(model: model).ignoresSafeArea()
            model.ambientColor.opacity(model.ambientOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Everything below sits inside the safe area, which on iPhone Duo
            // already includes the system's vertical bar column - no manual
            // inset math like the Flutter version needs.
            GeometryReader { geo in
                if workspace {
                    workspaceChrome
                } else {
                    phoneChrome(geo.size)
                }
                // Bottom trailing in every layout, next to the tab bar.
                cornerControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
            }

            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xFF323232)))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: workspace, initial: true) { _, isWorkspace in
            // The workspace panel has room to keep the sun readout open.
            if isWorkspace { model.showInfo = true }
        }
    }

    private var searchField: some View {
        LocationSearchField(controller: model.search, onSelect: model.select)
    }

    private var legend: some View {
        Legend(locationLabel: model.locationLabel, sunAlt: model.sunAlt, sunAz: model.sunAz,
               statusMsg: model.statusMsg, statusError: model.statusError)
    }

    private var timePanel: some View {
        BottomBar(model: model)
    }

    private var workspaceChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 12) {
                searchField
                ScrollView {
                    if model.showInfo { legend }
                }
            }
            .frame(width: workspacePanelWidth)
            // Full width under the panel so the time slider gets the room,
            // stopping short of the controls pill at the bottom trailing corner.
            timePanel
                .padding(.trailing, 44 + 12)
        }
        // 22pt from the top and leading edge so the panel's corners clear the
        // inner display's rounded corners.
        .padding(.top, 22)
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func phoneChrome(_ size: CGSize) -> some View {
        let compact = isCompactHeight(windowSize)
        // Open iPhone Duo (fully or half): no cap, so the time slider uses the
        // whole width up to the controls pill.
        let duoOpen = fold.hasHinge && fold.posture != .folded
        let barWidth = duoOpen ? size.width - 76 : min(420, size.width - 76)
        let compactSearchWidth = clampD(Double(size.width - 24 - legendWidth - 12 - 52), 200, 360)

        if compact {
            // Short windows: search top-leading, readout beside it.
            searchField
                .frame(width: compactSearchWidth)
                .padding([.top, .leading], 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            searchField
                .frame(width: min(360, size.width - 24))
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }

        if model.showInfo {
            Group {
                if compact {
                    ScrollView { legend }
                        .frame(width: legendWidth)
                        .frame(maxHeight: size.height / 2 - 24)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    legend.frame(width: legendWidth)
                }
            }
            .padding(.top, compact ? 12 : 76)
            // Compact windows keep clear of the controls pill on the right.
            .padding(.trailing, compact ? 64 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }

        timePanel
            .frame(width: max(0, barWidth))
            .padding(.leading, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var cornerControls: some View {
        CornerControls(model: model, collapsible: fold.hasHinge)
    }
}

// MARK: - Chrome

private struct Legend: View {
    @Environment(\.colorScheme) private var scheme
    let locationLabel: String
    let sunAlt: Double?
    let sunAz: Double?
    let statusMsg: String
    let statusError: Bool

    var body: some View {
        let isDark = scheme == .dark
        let onPanel = isDark ? Color(hex: 0xFFF2F2F2) : Color(hex: 0xFF1B1D22)
        let onPanelMuted = isDark ? Color(hex: 0xFFA4AAB2) : Color(hex: 0xFF52575E)
        let labelMuted = isDark ? Color(hex: 0xFF8A9099) : Color(hex: 0xFF61666D)
        let accent = isDark ? Color(hex: 0xFFFFD580) : Color(hex: 0xFF9C5300)

        VStack(alignment: .leading, spacing: 0) {
            Text("Shade Map Demo")
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(onPanel)
            Text("Real 3D buildings + computed sun-cast shadows — \(locationLabel)")
                .font(.system(size: 11))
                .lineSpacing(3)
                .foregroundStyle(onPanelMuted)
                .padding(.top, 6)
            HStack(alignment: .top) {
                readout("ALTITUDE", sunAlt.map { String(format: "%.1f°", $0) } ?? "--°", labelMuted, accent)
                readout("AZIMUTH", sunAz.map { String(format: "%.0f°", $0) } ?? "--°", labelMuted, accent)
            }
            .padding(.top, 9)
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(accent).frame(width: 9, height: 9)
                    .shadow(color: accent, radius: 3)
                    .padding(.top, 2)
                Text(statusMsg)
                    .font(.system(size: 10.5))
                    .lineSpacing(2)
                    .foregroundStyle(statusError ? Color(hex: 0xFFFF9A8A)
                        : (isDark ? Color(hex: 0xFF71C686) : Color(hex: 0xFF267A45)))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glass(radius: 18, tint: isDark ? Color(hex: 0xFF15171C) : lightPanelTint, opacity: isDark ? 0.5 : 0.7)
    }

    private func readout(_ label: LocalizedStringKey, _ value: String, _ labelColor: Color, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 10)).tracking(0.4).foregroundStyle(labelColor)
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compass, info, 2D/3D, satellite and locate grouped into one pill.
/// On iPhone Duo (`collapsible`) a toggle button sits under the pill so the
/// user can hide it; it starts shown.
private struct CornerControls: View {
    @Environment(\.colorScheme) private var scheme
    let model: ShadeMapModel
    var collapsible = false
    @State private var expanded = true

    var body: some View {
        if collapsible {
            VStack(spacing: 8) {
                if expanded {
                    pill.transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                }
                toggleButton
            }
        } else {
            pill
        }
    }

    /// Styled like the tab bar's selected item: its glass with the amber bubble on top.
    private var toggleButton: some View {
        let style = scheme == .dark ? AppTabBarStyle.dark : AppTabBarStyle.light
        return cornerButton(action: { withAnimation(.snappy) { expanded.toggle() } }) {
            Image(systemName: expanded ? "chevron.down" : "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(style.active)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 44)
        .background(ActiveIndicator(style: style, vertical: true))
        .glass(radius: 22, tint: style.glassTint, opacity: style.glassTintOpacity)
    }

    @ViewBuilder
    private var pill: some View {
        let isDark = scheme == .dark
        let icon = isDark ? Color(hex: 0xFFECEDEF) : Color(hex: 0xFF1B1D22)
        let compassLabel = isDark ? Color(hex: 0xFFDFE3E8) : Color(hex: 0xFF6B7078)
        let north = isDark ? Color(hex: 0xFFFF8A7A) : Color(hex: 0xFFE04B36)
        let tail = isDark ? Color(hex: 0xFF6F7580) : Color(hex: 0xFF9AA0A8)
        let gold = isDark ? Color(hex: 0xFFFFD580) : Color(hex: 0xFF9C5300)
        let divider = Rectangle().fill((isDark ? Color.white : Color.black).opacity(0.1)).frame(height: 1)

        VStack(spacing: 0) {
            cornerButton(height: 52, action: model.resetNorth) {
                ZStack {
                    // Cardinal letters, translated ("N" -> "北", "E" -> "O"…).
                    VStack { label("N", north); Spacer(); label("S", compassLabel) }
                    HStack { label("W", compassLabel); Spacer(); label("E", compassLabel) }
                    VStack(spacing: 0) {
                        Rectangle().fill(north).frame(width: 2, height: 8)
                        Rectangle().fill(tail).frame(width: 2, height: 8)
                    }
                }
                .frame(width: 38, height: 38)
                // W stays on the left, E on the right, in every language.
                .environment(\.layoutDirection, .leftToRight)
                .rotationEffect(.degrees(-model.bearing))
            }
            divider
            cornerButton(action: { model.showInfo.toggle() }) {
                Image(systemName: model.showInfo ? "xmark" : "info.circle")
                    .font(.system(size: 17)).foregroundStyle(icon)
            }
            divider
            cornerButton(action: model.toggleDimension) {
                Text(model.is3D ? "3D" : "2D")
                    .font(.system(size: 11, weight: .bold)).tracking(0.3).foregroundStyle(icon)
            }
            divider
            cornerButton(action: model.toggleSatellite) {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 16)).foregroundStyle(model.satellite ? gold : icon)
            }
            divider
            cornerButton(action: { model.goToCurrentLocation() }) {
                if model.locating {
                    ProgressView().controlSize(.small).tint(icon)
                } else {
                    Image(systemName: "location").font(.system(size: 16)).foregroundStyle(icon)
                }
            }
        }
        .frame(width: 44)
        .glass(radius: 20, tint: isDark ? Color(hex: 0xFF15171C) : lightPanelTint, opacity: 0.5)
    }

    private func label(_ s: LocalizedStringKey, _ c: Color) -> some View {
        Text(s).font(.system(size: 7.5, weight: .bold)).foregroundStyle(c)
    }

    private func cornerButton<C: View>(height: CGFloat = 44, action: @escaping () -> Void,
                                       @ViewBuilder content: () -> C) -> some View {
        Button(action: action) {
            content().frame(width: 44, height: height).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The floating time panel: big time, play, day slider, sunrise/sunset,
/// shadow strength.
private struct BottomBar: View {
    @Environment(\.colorScheme) private var scheme
    let model: ShadeMapModel

    var body: some View {
        let isDark = scheme == .dark
        let onPanel = isDark ? Color(hex: 0xFFEEEEEE) : Color(hex: 0xFF1B1D22)
        let muted = isDark ? Color(hex: 0xFF9AA0A8) : Color(hex: 0xFF6B7078)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(formatBigTime(model.minutes))
                        .font(.system(size: 19, weight: .bold)).tracking(0.3)
                        .foregroundStyle(onPanel)
                        .monospacedDigit()
                    Text(model.dateStr).font(.system(size: 12)).foregroundStyle(muted)
                }
                Spacer()
                PlayButton(playing: model.playing, action: model.togglePlaying)
            }
            TimeSlider(minutes: model.minutes, sunrise: model.sunrise, sunset: model.sunset,
                       isDark: isDark, onChange: model.setMinutes)
            HStack(spacing: 4) {
                Image(systemName: "sunrise.fill").font(.system(size: 11))
                    .foregroundStyle(accentForTheme(0xFFFFB74D, isDark).opacity(0.9))
                Text(formatHHmm(model.sunrise)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(muted)
                Spacer().frame(width: 10)
                Image(systemName: "moon.stars").font(.system(size: 11))
                    .foregroundStyle(accentForTheme(0xFF8B93FF, isDark).opacity(0.9))
                Text(formatHHmm(model.sunset)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(muted)
            }
            .padding(.top, 6)
            HStack {
                Text("Shadow strength").font(.system(size: 10.5)).foregroundStyle(muted).lineLimit(1)
                Spacer()
                Slider(value: Binding(get: { Double(model.opacity) },
                                      set: { model.setOpacity(Int($0.rounded())) }), in: 0...100)
                    .tint(AppTabBarStyle.accent)
                    .controlSize(.mini)
                    .frame(width: 110)
            }
            .padding(.top, 4)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 14, trailing: 20))
        .glass(radius: kCardRadius, tint: isDark ? Color(hex: 0xFF15171C) : .white, opacity: isDark ? 0.6 : 0.75)
    }
}
