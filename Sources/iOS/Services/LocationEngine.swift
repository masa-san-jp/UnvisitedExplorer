import CoreLocation
import Foundation

/// 記録エンジン(仕様 §3.1 の L0 / L1 / L2)。
///
/// SwiftUI の Scene ライフサイクルから切り離した singleton にしている。
/// `@StateObject(wrappedValue:)` は autoclosure であり Scene の body が評価される
/// まで生成されないため、UI に紐づけるとバックグラウンド起動時に delegate すら
/// 設定されず、位置イベントが誰にも配信されないままプロセスが終了する。
@MainActor
final class LocationEngine: NSObject, ObservableObject {
    static let shared = LocationEngine()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRecording = false
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var lastError: String?
    /// 直近の起動が位置イベントによるバックグラウンド起動だったか(動作確認用)。
    @Published private(set) var launchedForLocationEvent = false

    let store: LocationStore

    private let manager = CLLocationManager()

    /// アンカーを張る基準。記録用の `latestLocation` とは別に持つ。
    ///
    /// 記録は精度フィルタを通すが、アンカーは「いま自分がどこにいるか」を表すだけなので
    /// フィルタを通す必要がない。ここを `latestLocation` で兼用すると、精度の悪い測位が
    /// 続いたときに離脱済みの古い位置へ再登録し、即座にまた離脱する狭いループになる。
    private var lastKnownCoordinate: CLLocationCoordinate2D?

    /// L2 の追尾アンカー。常に同じ identifier で張り替え、リージョンを溜めない。
    private static let anchorIdentifier = "trail.anchor"
    private static let anchorRadius: CLLocationDistance = 150
    /// この距離未満の移動では張り替えない(無駄な登録の抑制)。
    private static let anchorRefreshThreshold: CLLocationDistance = 20

    private override init() {
        store = LocationStore(container: Persistence.container)
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
    }

    func noteLaunchedForLocationEvent() {
        launchedForLocationEvent = true
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// 起動時に無条件で呼ぶ。UI の表示を待たない。
    ///
    /// `CLLocationManager.locationServicesEnabled()` はブロックしうるため事前確認せず、
    /// 無効時は delegate のエラーで受ける。
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            lastError = "位置情報の利用が許可されていません。"
            isRecording = false
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return
        }

        let isAlways = manager.authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = isAlways

        manager.startMonitoringSignificantLocationChanges()  // L0

        if isAlways {
            manager.startMonitoringVisits()                  // L1
            if anchorRegion == nil, manager.location == nil {
                // アンカーを張る基準点がまだない。単発測位でチェーンを起こす。
                manager.requestLocation()
            } else {
                refreshAnchor()                              // L2
            }
        }

        isRecording = true
        lastError = nil
    }

    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        removeAnchor()
        isRecording = false
    }

    /// フォアグラウンド復帰時などに呼ぶ。L2 のチェーンが切れていても復旧できる。
    func refreshAnchorIfPossible() {
        refreshAnchor()
    }

    // MARK: - L2 追尾ジオフェンス

    private var anchorRegion: CLCircularRegion? {
        manager.monitoredRegions.first { $0.identifier == Self.anchorIdentifier } as? CLCircularRegion
    }

    /// 現在地を中心にアンカーを張り直す。
    ///
    /// 再登録の経路を1つに依存させない。`didExitRegion` → `requestLocation()` が
    /// 失敗するとチェーンが切れ、L2 が無言で停止するため、L0/L1 の配信時・
    /// エラー時・フォアグラウンド復帰時にも張り直す。
    private func refreshAnchor(at coordinate: CLLocationCoordinate2D? = nil) {
        guard manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              let center = coordinate ?? lastKnownCoordinate ?? manager.location?.coordinate
        else { return }

        if let existing = anchorRegion {
            let moved = CLLocation(latitude: center.latitude, longitude: center.longitude)
                .distance(
                    from: CLLocation(
                        latitude: existing.center.latitude,
                        longitude: existing.center.longitude
                    )
                )
            if moved < Self.anchorRefreshThreshold { return }
        }

        removeAnchor()

        let radius = min(Self.anchorRadius, manager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(
            center: center,
            radius: radius,
            identifier: Self.anchorIdentifier
        )
        region.notifyOnEntry = false
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }

    private func removeAnchor() {
        for region in manager.monitoredRegions where region.identifier == Self.anchorIdentifier {
            manager.stopMonitoring(for: region)
        }
    }

    // MARK: - 記録

    private func record(_ location: CLLocation) {
        let payload = LocationPayload(
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
        if store.ingest(payload) == .accept {
            latestLocation = location
        }
    }

    private func record(_ visit: CLVisit) {
        let timestamp = RecordingPolicy.visitTimestamp(
            arrival: visit.arrivalDate,
            departure: visit.departureDate,
            now: Date()
        )
        store.ingest(
            LocationPayload(
                timestamp: timestamp,
                latitude: visit.coordinate.latitude,
                longitude: visit.coordinate.longitude,
                altitude: 0,
                horizontalAccuracy: visit.horizontalAccuracy,
                verticalAccuracy: -1,
                speed: -1,
                course: -1,
                source: .iPhone
            )
        )
    }
}

extension LocationEngine: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = self.manager.authorizationStatus
            switch self.manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                start()
            default:
                isRecording = false
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            // アンカーの基準は精度フィルタを通す前の生の位置を使う。
            if let newest = locations.last {
                lastKnownCoordinate = newest.coordinate
            }
            for location in locations {
                record(location)
            }
            refreshAnchor()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            lastKnownCoordinate = visit.coordinate
            record(visit)
            refreshAnchor(at: visit.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let identifier = region.identifier
        Task { @MainActor in
            guard identifier == Self.anchorIdentifier else { return }
            // 離脱イベントは座標を持たないため単発測位する。
            // 結果は didUpdateLocations に届き、そこでアンカーが張り直される。
            self.manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            refreshAnchor()
        }
    }
}
