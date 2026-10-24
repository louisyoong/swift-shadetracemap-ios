import SwiftUI
import MapLibre
import Observation

private let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
private let centerKL = CLLocationCoordinate2D(latitude: 3.1412, longitude: 101.68653)
private let initialUtcOffset = 8 // Asia/Kuala_Lumpur
private let buildingLayerId = "building-3d" // native layer in the "liberty" style
private let satelliteSourceId = "satellite-source"
private let satelliteLayerId = "satellite-layer"
private let satelliteTileURL = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
private let coreFill = UIColor(red: 0x15 / 255, green: 0x1B / 255, blue: 0x33 / 255, alpha: 1)
private let softFill = UIColor(red: 0x1C / 255, green: 0x24 / 255, blue: 0x40 / 255, alpha: 1)

/// All Shade Map state and logic - the Swift counterpart of
/// _ShadeMapScreenState in shade_map_screen.dart.
@MainActor
@Observable
final class ShadeMapModel {
    var dateStr: String
    var minutes: Int
    var utcOffsetHours = initialUtcOffset

    var opacity = 65
    private(set) var playing = false

    private(set) var sunAlt: Double?
    private(set) var sunAz: Double?
    private(set) var sunrise: Int?
    private(set) var sunset: Int?

    private(set) var statusMsg = String(localized: "Loading map…", bundle: AppLanguage.bundle)
    private(set) var statusError = false
    private(set) var locationLabel = String(localized: "Kuala Lumpur, Malaysia", bundle: AppLanguage.bundle)

    private(set) var ambientColor = Color(hex: 0xFF3A4A73)
    private(set) var ambientOpacity = 0.0

    private(set) var bearing = -12.0
    private(set) var tilt = 58.0
    var is3D: Bool { tilt > 5 }
    var showInfo = false
    private(set) var satellite = false
    private(set) var locating = false
    var toast: String?

    let search = LocationSearchController()

    @ObservationIgnored weak var mapView: MLNMapView?
    @ObservationIgnored private var styleLoaded = false
    @ObservationIgnored private var shadowsReady = false
    @ObservationIgnored private var recomputeGen = 0
    @ObservationIgnored private var recomputeBusy = false
    @ObservationIgnored private var recomputeQueued = false
    @ObservationIgnored private var lastSunTimesKey = ""
    @ObservationIgnored private var playTimer: Timer?

    init() {
        let f = localFieldsFromInstant(nowMs(), offsetHours: initialUtcOffset)
        dateStr = dateString(from: f)
        minutes = f.minutesOfDay
    }

    private var currentInstantMs: Int {
        instantMs(dateStr: dateStr, minutes: minutes, offsetHours: utcOffsetHours)
    }

    // MARK: - Map setup

    func makeMapView() -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.setCenter(centerKL, zoomLevel: 16.4, animated: false)
        map.compassView.isHidden = true
        // The MapLibre logo isn't required; the "i" attribution button stays,
        // since the OpenStreetMap data behind the tiles must be credited.
        map.logoView.isHidden = true
        mapView = map
        return map
    }

    func onStyleLoaded(_ style: MLNStyle) {
        guard !styleLoaded, let map = mapView else { return }
        styleLoaded = true

        let building = style.layer(withIdentifier: buildingLayerId)
        let v = Double(opacity) / 100
        for (id, color, maxOpacity) in [("shadow-soft", softFill, softMaxOpacity), ("shadow-core", coreFill, coreMaxOpacity)] {
            let source = MLNShapeSource(identifier: id, shape: nil, options: nil)
            style.addSource(source)
            let layer = MLNFillStyleLayer(identifier: "\(id)-layer", source: source)
            layer.fillColor = NSExpression(forConstantValue: color)
            layer.fillOpacity = NSExpression(forConstantValue: maxOpacity * v)
            if let building { style.insertLayer(layer, below: building) } else { style.addLayer(layer) }
        }

        // Satellite imagery under the shadows; toggling just flips visibility.
        let sat = MLNRasterTileSource(identifier: satelliteSourceId, tileURLTemplates: [satelliteTileURL],
                                      options: [.tileSize: 256])
        style.addSource(sat)
        let satLayer = MLNRasterStyleLayer(identifier: satelliteLayerId, source: sat)
        satLayer.isVisible = satellite
        if let soft = style.layer(withIdentifier: "shadow-soft-layer") { style.insertLayer(satLayer, below: soft) }

        shadowsReady = true
        statusMsg = String(localized: "Map loaded. Rendering buildings…", bundle: AppLanguage.bundle)
        statusError = false

        // Natively there's no cold-launch race to work around (the Flutter
        // plugin crashed if tilt was set too early), so tilt right away.
        let cam = map.camera
        cam.pitch = 58
        cam.heading = 348 // -12°
        map.setCamera(cam, animated: false)

        scheduleRecompute()
        // Catch tiles still loading at style-load time.
        for delay in [0.8, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scheduleRecompute() }
        }
        goToCurrentLocation(silent: true)
    }

    func onCameraMoving() {
        guard let map = mapView else { return }
        bearing = map.direction
        tilt = map.camera.pitch
    }

    // MARK: - Shadows

    private func ambientOverlay(for pos: SunPosition) -> (Color, Double) {
        if pos.altitude <= 0.5 { return (Color(hex: 0xFF3A4A73), 0.34) }
        let t = clampD(pos.altitude / 90, 0, 1)
        let intensity = clampD(0.28 + 0.42 * t, 0.28, 0.7)
        if pos.altitude < 12 { return (Color(hex: 0xFFFFC48F), 0.20) }
        return (.white, (1 - intensity) * 0.14)
    }

    /// At most one recompute in flight plus one queued, so fast slider drags
    /// and play-mode ticks only ever draw the latest time.
    func scheduleRecompute() {
        if recomputeBusy {
            recomputeQueued = true
            return
        }
        recomputeBusy = true
        Task {
            await recompute()
            while recomputeQueued {
                recomputeQueued = false
                await recompute()
            }
            recomputeBusy = false
        }
    }

    private func recompute() async {
        guard let map = mapView, styleLoaded else { return }
        recomputeGen += 1
        let gen = recomputeGen

        let center = map.centerCoordinate
        let instant = currentInstantMs
        let pos = sunPosition(instantMs: Double(instant), lat: center.latitude, lon: center.longitude)
        let overlay = ambientOverlay(for: pos)

        var count = 0
        if shadowsReady {
            count = await drawShadows(map, pos: pos, gen: gen)
        }
        guard gen == recomputeGen else { return }

        let dayStart = localMidnightMs(instant, offsetHours: utcOffsetHours)
        let key = "\(dayStart)@\(String(format: "%.2f,%.2f", center.latitude, center.longitude))"
        if key != lastSunTimesKey {
            lastSunTimesKey = key
            let times = findSunriseSunset(dayStartMs: dayStart, lat: center.latitude, lon: center.longitude)
            sunrise = times.sunrise
            sunset = times.sunset
        }

        if pos.altitude <= 0.5 {
            statusMsg = String(localized: "Sun below horizon — no shadows right now.", bundle: AppLanguage.bundle)
            statusError = false
        } else if shadowsReady {
            if map.zoomLevel < 14 {
                statusMsg = String(localized: "Zoom in (≥14) to see buildings and their shadows.", bundle: AppLanguage.bundle)
                statusError = true
            } else {
                statusMsg = String(localized: "Casting shadows for \(count) buildings in view.", bundle: AppLanguage.bundle)
                statusError = false
            }
        }
        sunAlt = pos.altitude
        sunAz = pos.azimuth
        withAnimation(.easeInOut(duration: 0.4)) {
            ambientColor = overlay.0
            ambientOpacity = overlay.1
        }
    }

    private struct Footprint: Sendable {
        let ring: [CLLocationCoordinate2D]
        let height: Double
    }

    private func drawShadows(_ map: MLNMapView, pos: SunPosition, gen: Int) async -> Int {
        guard let style = map.style,
              let core = style.source(withIdentifier: "shadow-core") as? MLNShapeSource,
              let soft = style.source(withIdentifier: "shadow-soft") as? MLNShapeSource else { return 0 }
        if pos.altitude <= 0.5 {
            core.shape = nil
            soft.shape = nil
            return 0
        }

        // The query has to run on the main thread; the hull math doesn't, so
        // it moves to a background task and the map stays smooth.
        var footprints: [Footprint] = []
        for feature in map.visibleFeatures(in: map.bounds, styleLayerIdentifiers: [buildingLayerId]) {
            let polygons: [MLNPolygon]
            if let p = feature as? MLNPolygonFeature {
                polygons = [p]
            } else if let mp = feature as? MLNMultiPolygonFeature {
                polygons = mp.polygons
            } else {
                continue
            }
            let height = buildingHeight(of: feature.attributes)
            for p in polygons {
                let ring = Array(UnsafeBufferPointer(start: p.coordinates, count: Int(p.pointCount)))
                footprints.append(Footprint(ring: ring, height: height))
            }
        }

        let shadowAz = norm360(pos.azimuth + 180)
        let baseLen = min(1 / max(tan(toRad(pos.altitude)), 0.02), maxShadowLen)
        let (coreRings, softRings) = await Task.detached(priority: .userInitiated) {
            var seen = Set<String>()
            var coreRings: [[CLLocationCoordinate2D]] = []
            var softRings: [[CLLocationCoordinate2D]] = []
            for fp in footprints {
                let lenM = min(fp.height * baseLen, maxShadowLen)
                guard lenM >= 1, fp.ring.count >= 4 else { continue }
                let first = fp.ring[0]
                let key = String(format: "%.5f,%.5f,%.0f", first.longitude, first.latitude, fp.height)
                guard seen.insert(key).inserted else { continue }
                let verts = Array(fp.ring.dropLast())
                guard verts.count >= 3 else { continue }

                let hull = convexHull(verts + verts.map { offsetPoint($0, distM: lenM, bearingDeg: shadowAz) })
                if hull.count >= 3 { coreRings.append(hull + [hull[0]]) }
                let lenSoft = min(lenM * 1.35, maxShadowLen * 1.3)
                let hullSoft = convexHull(verts + verts.map { offsetPoint($0, distM: lenSoft, bearingDeg: shadowAz) })
                if hullSoft.count >= 3 { softRings.append(hullSoft + [hullSoft[0]]) }
            }
            return (coreRings, softRings)
        }.value

        guard gen == recomputeGen else { return coreRings.count }
        func collection(_ rings: [[CLLocationCoordinate2D]]) -> MLNShapeCollectionFeature {
            MLNShapeCollectionFeature(shapes: rings.map { MLNPolygonFeature(coordinates: $0, count: UInt($0.count)) })
        }
        core.shape = collection(coreRings)
        soft.shape = collection(softRings)
        return coreRings.count
    }

    // MARK: - Controls

    func onWallClockChanged() { scheduleRecompute() }

    func setMinutes(_ m: Int) {
        minutes = m
        onWallClockChanged()
    }

    func togglePlaying() {
        playing.toggle()
        if playing {
            playTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.setMinutes((self.minutes + 5) % 1440)
                }
            }
        } else {
            playTimer?.invalidate()
            playTimer = nil
        }
    }

    func setOpacity(_ value: Int) {
        opacity = value
        guard shadowsReady, let style = mapView?.style else { return }
        let v = Double(value) / 100
        (style.layer(withIdentifier: "shadow-core-layer") as? MLNFillStyleLayer)?.fillOpacity =
            NSExpression(forConstantValue: coreMaxOpacity * v)
        (style.layer(withIdentifier: "shadow-soft-layer") as? MLNFillStyleLayer)?.fillOpacity =
            NSExpression(forConstantValue: softMaxOpacity * v)
    }

    func toggleSatellite() {
        satellite.toggle()
        mapView?.style?.layer(withIdentifier: satelliteLayerId)?.isVisible = satellite
    }

    func resetNorth() { mapView?.setDirection(0, animated: true) }

    func toggleDimension() {
        guard let map = mapView else { return }
        let cam = map.camera
        cam.pitch = map.camera.pitch <= 5 ? 58 : 0
        map.setCamera(cam, withDuration: 0.5, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
    }

    /// Moves the map to `coord`, keeping the user's current 2D/3D angle and
    /// rotation, and jumps the clock to "now" there.
    private func moveTo(_ coord: CLLocationCoordinate2D, label: String) {
        mapView?.setCenter(coord, zoomLevel: 16.4, direction: mapView?.direction ?? 0, animated: true)
        let offset = approxUtcOffsetHours(coord.longitude)
        let f = localFieldsFromInstant(nowMs(), offsetHours: offset)
        utcOffsetHours = offset
        dateStr = dateString(from: f)
        minutes = f.minutesOfDay
        locationLabel = label
        search.selected(label)
        onWallClockChanged()
    }

    func select(_ place: Place) {
        moveTo(CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon), label: place.shortLabel)
    }

    /// `silent` is the automatic on-launch detection: a denied location just
    /// keeps the Kuala Lumpur default instead of showing an error.
    func goToCurrentLocation(silent: Bool = false) {
        guard mapView != nil, !locating else { return }
        locating = true
        Task {
            defer { locating = false }
            do {
                let loc = try await DeviceLocation.shared.current()
                moveTo(loc.coordinate, label: String(localized: "My Location", bundle: AppLanguage.bundle))
                if let label = await reverseGeocodeLabel(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude) {
                    locationLabel = label
                    search.selected(label)
                }
            } catch {
                if !silent { showToast((error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn't determine your location.", bundle: AppLanguage.bundle)) }
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if toast == message { withAnimation { toast = nil } }
        }
    }
}
