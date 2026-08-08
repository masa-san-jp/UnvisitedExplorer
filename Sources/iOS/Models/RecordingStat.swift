import Foundation
import SwiftData

/// レイヤーごとの採用・棄却の集計(仕様 §10.3)。
///
/// バックグラウンド起動は毎回新しいプロセスになるため、メモリ上の
/// カウンタでは「アプリを開いていない間に何が起きたか」が残らない。永続化する。
@Model
final class RecordingStat {
    @Attribute(.unique) var layerRawValue: String
    var accepted: Int
    var rejected: Int
    /// 採用・棄却を問わず、その層から最後に配信があった時刻。
    var lastFiredAt: Date?
    var lastAcceptedAt: Date?

    init(layer: RecordingLayer) {
        layerRawValue = layer.rawValue
        accepted = 0
        rejected = 0
    }

    var layer: RecordingLayer {
        RecordingLayer(rawValue: layerRawValue) ?? .unknown
    }
}
