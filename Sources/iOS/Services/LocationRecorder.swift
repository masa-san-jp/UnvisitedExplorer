import CoreLocation
import Foundation

@MainActor
final class LocationRecorder: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRecording = false
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private let ingest: @MainActor (LocationPayload) -> Void
    private var lastAcceptedLocation: CLLocation?

    init(ingest: @escaping @MainActor (LocationPayload) -> Void) {
        self.ingest = ingest
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 75
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startRecording() {
        guard CLLocationManager.locationServicesEnabled() else {
            lastError = "端末の位置情報サービスが無効です。"
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            lastError = "位置情報の利用が許可されていません。"
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return
        }

        manager.allowsBackgroundLocationUpdates = manager.authorizationStatus == .authorizedAlways
        manager.showsBackgroundLocationIndicator = manager.authorizationStatus != .authorizedAlways
        manager.startMonitoringSignificantLocationChanges()
        manager.startUpdatingLocation()
        isRecording = true
        lastError = nil
    }

    func stopRecording() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        isRecording = false
    }

    private func accept(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 500 else { return false }
        guard abs(location.timestamp.timeIntervalSinceNow) < 300 else { return false }

        if let last = lastAcceptedLocation {
            let seconds = location.timestamp.timeIntervalSince(last.timestamp)
            if seconds < 30, location.distance(from: last) < 25 { return false }
        }
        lastAcceptedLocation = location
        return true
    }
}

extension LocationRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways ||
                manager.authorizationStatus == .authorizedWhenInUse {
                startRecording()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations where accept(location) {
                latestLocation = location
                ingest(
                    LocationPayload(
                        timestamp: location.timestamp,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        altitude: location.altitude,
                        horizontalAccuracy: location.horizontalAccuracy,
                        verticalAccuracy: location.verticalAccuracy,
                        speed: location.speed,
                        course: location.course,
                        source: .iPhone
                    )
                )
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }
}
