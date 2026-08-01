import CoreLocation
import Foundation

@MainActor
final class WatchLocationRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var sampleCount = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private let sender: WatchConnectivitySender
    private var lastAcceptedLocation: CLLocation?

    init(sender: WatchConnectivitySender) {
        self.sender = sender
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 40
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = true
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            lastError = "位置情報を許可してください。"
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return
        }

        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isRecording = true
        lastError = nil
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRecording = false
    }

    private func accept(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 200 else { return false }
        if let previous = lastAcceptedLocation,
           location.timestamp.timeIntervalSince(previous.timestamp) < 20,
           location.distance(from: previous) < 20 {
            return false
        }
        lastAcceptedLocation = location
        return true
    }
}

extension WatchLocationRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways ||
                manager.authorizationStatus == .authorizedWhenInUse {
                start()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations where accept(location) {
                let payload = LocationPayload(
                    timestamp: location.timestamp,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: location.altitude,
                    horizontalAccuracy: location.horizontalAccuracy,
                    verticalAccuracy: location.verticalAccuracy,
                    speed: location.speed,
                    course: location.course,
                    source: .appleWatch
                )
                sender.enqueue(payload)
                sampleCount += 1
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in lastError = error.localizedDescription }
    }
}
