import Foundation
import SwiftData

/// `ModelContainer` の生成箇所を1つに固定する。
///
/// 記録エンジンと SwiftUI の `.modelContainer(_:)` が別々にコンテナを作ると、
/// 記録先と `@Query` の参照先が別DBになり、書き出しても中身が空になる。
@MainActor
enum Persistence {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: LocationSample.self, VisitedCell.self, RecordingStat.self
            )
        } catch {
            fatalError("SwiftDataの初期化に失敗しました: \(error)")
        }
    }()
}
