import CoreLocation
import Foundation

/// 取り込み経路の種別。鮮度フィルタの適用有無だけが異なる(仕様 §3.5)。
///
/// 連想値がないため Equatable は暗黙に得られるが、public な型の契約として明示する。
public enum IngestPolicy: Sendable, Equatable {
    /// L0〜L4 / Watch からのリアルタイム配信。
    case live
    /// インポートした過去データ。
    case historical
}

/// 記録フィルタの閾値。仕様 §3.5 の唯一の定義箇所。
public enum RecordingPolicy {
    /// 誤差がセル半径を超える測位を採用すると、通っていないセルが踏破済みになる。
    /// 訂正UIを持たないため、欠損より誤記録を避ける。
    public static let maxHorizontalAccuracy = min(100.0, GeoGrid.defaultCellSizeMeters / 2)
    public static let minInterval: TimeInterval = 60
    public static let minDistance: CLLocationDistance = 50
    public static let maxAge: TimeInterval = 300

    /// `CLVisit` の日付は `arrivalDate` が `.distantPast`、`departureDate` が
    /// `.distantFuture` になりうるため、そのまま保存すると時系列が壊れる。
    public static func visitTimestamp(arrival: Date, departure: Date, now: Date) -> Date {
        if departure != .distantFuture, departure != .distantPast { return departure }
        if arrival != .distantPast, arrival != .distantFuture { return arrival }
        return now
    }
}

/// 直前に採用した地点。重複排除の基準になる。
public struct AcceptedPoint: Sendable, Equatable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double

    public init(timestamp: Date, latitude: Double, longitude: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// 純粋関数としての入力フィルタ。SwiftData に依存しないためユニットテストできる。
public enum RecordingFilter {
    public enum Decision: Equatable, Sendable {
        case accept
        case rejectAccuracy
        case rejectCoordinate
        case rejectStale
        case rejectDuplicate
    }

    public static func decide(
        _ payload: LocationPayload,
        lastAccepted: AcceptedPoint?,
        now: Date,
        policy: IngestPolicy
    ) -> Decision {
        guard payload.horizontalAccuracy >= 0,
              payload.horizontalAccuracy <= RecordingPolicy.maxHorizontalAccuracy else {
            return .rejectAccuracy
        }
        guard abs(payload.latitude) <= 90, abs(payload.longitude) <= 180 else {
            return .rejectCoordinate
        }
        if policy == .live,
           abs(payload.timestamp.timeIntervalSince(now)) > RecordingPolicy.maxAge {
            return .rejectStale
        }

        if let last = lastAccepted {
            let seconds = abs(payload.timestamp.timeIntervalSince(last.timestamp))
            let meters = CLLocation(latitude: payload.latitude, longitude: payload.longitude)
                .distance(
                    from: CLLocation(latitude: last.latitude, longitude: last.longitude)
                )
            if seconds < RecordingPolicy.minInterval, meters < RecordingPolicy.minDistance {
                return .rejectDuplicate
            }
        }
        return .accept
    }
}
