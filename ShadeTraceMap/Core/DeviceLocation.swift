import CoreLocation

/// Thrown by `DeviceLocation.shared.current()` with a user-facing message.
struct DeviceLocationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Resolves the device's current GPS position. Every tab asks on launch, so
/// concurrent callers share one in-flight request instead of racing the
/// permission prompt (same reason as the Flutter app's in-flight cache).
@MainActor
final class DeviceLocation: NSObject, CLLocationManagerDelegate {
    static let shared = DeviceLocation()

    private let manager = CLLocationManager()
    private var inFlight: Task<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func current() async throws -> CLLocation {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await resolve() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func resolve() async throws -> CLLocation {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { c in
                authContinuation = c
                manager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw DeviceLocationError(message: String(localized: "Location permission denied.", bundle: AppLanguage.bundle))
        }
        // Checked after permission: on iOS the services check is a blocking
        // call Apple asks not to make on the main thread before authorization.
        let servicesOn = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        guard servicesOn else { throw DeviceLocationError(message: String(localized: "Location services are off.", bundle: AppLanguage.bundle)) }
        return try await withCheckedThrowingContinuation { c in
            locationContinuation = c
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor in
            authContinuation?.resume(returning: status)
            authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: loc)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: DeviceLocationError(message: String(localized: "Couldn't determine your location.", bundle: AppLanguage.bundle)))
            locationContinuation = nil
        }
    }
}
