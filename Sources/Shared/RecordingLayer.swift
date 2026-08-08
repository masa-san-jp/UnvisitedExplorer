import Foundation

/// 位置がどの経路で届いたか(仕様 §3.1)。
///
/// フィールドテスト(§10.3)でレイヤー別の採用/棄却件数を見るために使う。
/// どの層が動いていないのかは実機でしか分からず、内訳が無いと切り分けられない。
public enum RecordingLayer: String, Codable, Sendable, CaseIterable {
    case significantChange
    case visit
    case geofence
    case heartbeat
    case precise
    case watch
    case imported
    /// 経路を特定できなかったもの。
    case unknown

    public var label: String {
        switch self {
        case .significantChange: return "L0 大幅移動"
        case .visit: return "L1 滞在"
        case .geofence: return "L2 追尾"
        case .heartbeat: return "L3 定期"
        case .precise: return "L4 精密"
        case .watch: return "Watch"
        case .imported: return "取り込み"
        case .unknown: return "不明"
        }
    }

    /// 記録タブに出す順。
    public static let displayOrder: [RecordingLayer] = [
        .significantChange, .visit, .geofence, .heartbeat, .precise, .watch, .imported, .unknown
    ]
}
