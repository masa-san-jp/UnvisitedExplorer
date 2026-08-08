import CoreLocation
import Foundation
import SwiftData

/// 一括取り込みの結果。
struct ImportSummary: Equatable {
    var accepted = 0
    /// 精度・重複排除で弾かれた件数。
    var rejected = 0
    /// すでに取り込み済みだった件数(同じファイルの再投入)。
    var duplicated = 0
    var newCells = 0
    /// 保存に失敗した場合の理由。設定されていれば取り込みは途中で打ち切られている。
    var failure: String?

    var isSuccess: Bool { failure == nil }
}

/// `ingest` の結果。棄却と保存失敗を呼び出し元が区別できるようにする。
enum IngestOutcome: Equatable {
    case accepted
    case rejected(RecordingFilter.Decision)
    /// 永続化に失敗した。記録は残っていない。
    case failed(String)
}

/// 全入力の唯一の入口(仕様 §3.5)。
/// L0〜L4 / Watch / インポートは必ずここを通す。フィルタを他所に分散させない。
@MainActor
final class LocationStore: ObservableObject {
    let container: ModelContainer
    private let context: ModelContext

    /// 重複排除の基準点。バックグラウンド起動は毎回新しいプロセスなので、
    /// メモリ上の状態だけに頼ると起動のたびに重複排除がリセットされる。
    private var lastAccepted: AcceptedPoint?

    init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
        // 自動保存を切り、保存の成否を ingest が必ず把握できるようにする。
        // 変更経路は ingest と deleteAll だけで、どちらも明示的に save する。
        context.autosaveEnabled = false
        lastAccepted = Self.loadLastAccepted(from: context)
    }

    @discardableResult
    func ingest(
        _ payload: LocationPayload,
        layer: RecordingLayer = .unknown,
        policy: IngestPolicy = .live,
        now: Date = Date()
    ) -> IngestOutcome {
        let decision = RecordingFilter.decide(
            payload,
            lastAccepted: lastAccepted,
            now: now,
            policy: policy
        )
        guard decision == .accept else {
            note(layer: layer, accepted: false, at: now)
            // 棄却時はここで打ち切るので、集計だけを確定させる。
            try? context.save()
            return .rejected(decision)
        }

        let payloadID = payload.id
        var duplicateDescriptor = FetchDescriptor<LocationSample>(
            predicate: #Predicate { $0.id == payloadID }
        )
        duplicateDescriptor.fetchLimit = 1
        if (try? context.fetch(duplicateDescriptor).first) != nil {
            note(layer: layer, accepted: false, at: now)
            try? context.save()
            return .rejected(.rejectDuplicate)
        }

        let cell = GeoGrid.cell(
            for: CLLocationCoordinate2D(
                latitude: payload.latitude,
                longitude: payload.longitude
            )
        )
        context.insert(LocationSample(payload: payload, gridKey: cell.key, layer: layer))
        note(layer: layer, accepted: true, at: now)

        let cellKey = cell.key
        var cellDescriptor = FetchDescriptor<VisitedCell>(
            predicate: #Predicate { $0.key == cellKey }
        )
        cellDescriptor.fetchLimit = 1

        if let existing = try? context.fetch(cellDescriptor).first {
            existing.lastVisitedAt = max(existing.lastVisitedAt, payload.timestamp)
            existing.firstVisitedAt = min(existing.firstVisitedAt, payload.timestamp)
            existing.visitCount += 1
        } else {
            context.insert(VisitedCell(cell: cell, timestamp: payload.timestamp))
        }

        do {
            try context.save()
        } catch {
            // 保存できていないのに重複排除の基準を進めると、後続点が
            // 「記録済み」として捨てられ、欠損が連鎖する。
            context.rollback()
            return .failed(error.localizedDescription)
        }

        lastAccepted = AcceptedPoint(
            timestamp: payload.timestamp,
            latitude: payload.latitude,
            longitude: payload.longitude
        )
        return .accepted
    }

    /// 過去データの一括取り込み(仕様 §8)。
    ///
    /// 1点ずつ `ingest` を呼ぶと、点ごとに fetch と save が走って数万件で実用にならない。
    /// 既存 ID とセルを先に読み込み、保存はまとめて行う。フィルタは §3.5 と同じものを使う。
    func ingestHistorical(_ payloads: [LocationPayload]) -> ImportSummary {
        var summary = ImportSummary()
        guard !payloads.isEmpty else { return summary }

        // 重複排除は直前の採用点と比較するため、時系列に並べないと意味を持たない。
        let ordered = payloads.sorted { $0.timestamp < $1.timestamp }

        var knownIDs = Set(
            ((try? context.fetch(FetchDescriptor<LocationSample>())) ?? []).map(\.id)
        )
        var cells = Dictionary(
            (((try? context.fetch(FetchDescriptor<VisitedCell>())) ?? []).map { ($0.key, $0) }),
            uniquingKeysWith: { first, _ in first }
        )

        var pending = 0
        for payload in ordered {
            guard !knownIDs.contains(payload.id) else {
                summary.duplicated += 1
                continue
            }

            let decision = RecordingFilter.decide(
                payload,
                lastAccepted: lastAccepted,
                now: Date(),
                policy: .historical
            )
            guard decision == .accept else {
                summary.rejected += 1
                continue
            }

            let cell = GeoGrid.cell(
                for: CLLocationCoordinate2D(
                    latitude: payload.latitude,
                    longitude: payload.longitude
                )
            )
            context.insert(
                LocationSample(payload: payload, gridKey: cell.key, layer: .imported)
            )
            knownIDs.insert(payload.id)

            if let existing = cells[cell.key] {
                existing.lastVisitedAt = max(existing.lastVisitedAt, payload.timestamp)
                existing.firstVisitedAt = min(existing.firstVisitedAt, payload.timestamp)
                existing.visitCount += 1
            } else {
                let created = VisitedCell(cell: cell, timestamp: payload.timestamp)
                context.insert(created)
                cells[cell.key] = created
                summary.newCells += 1
            }

            lastAccepted = AcceptedPoint(
                timestamp: payload.timestamp,
                latitude: payload.latitude,
                longitude: payload.longitude
            )
            summary.accepted += 1
            pending += 1

            if pending >= Self.importBatchSize {
                guard flush(&summary) else { return summary }
                pending = 0
            }
        }

        // 集計は点ごとに fetch すると遅いので、最後にまとめて反映する。
        noteBulk(
            layer: .imported,
            accepted: summary.accepted,
            rejected: summary.rejected + summary.duplicated,
            at: Date()
        )
        guard flush(&summary) else { return summary }

        // 取り込み後は最新の点を基準に戻す。取り込んだ末尾は過去日時のことがある。
        lastAccepted = Self.loadLastAccepted(from: context)
        return summary
    }

    private static let importBatchSize = 500

    private func flush(_ summary: inout ImportSummary) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            summary.failure = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteAll(samples: [LocationSample], cells: [VisitedCell]) -> Bool {
        samples.forEach(context.delete)
        cells.forEach(context.delete)
        // 集計だけ残ると、全削除したのに件数が出続けることになる。
        ((try? context.fetch(FetchDescriptor<RecordingStat>())) ?? []).forEach(context.delete)
        do {
            try context.save()
        } catch {
            context.rollback()
            return false
        }
        lastAccepted = nil
        return true
    }

    /// レイヤー別の集計を進める(仕様 §10.3)。保存は呼び出し側に任せる。
    private func note(layer: RecordingLayer, accepted: Bool, at date: Date) {
        noteBulk(
            layer: layer,
            accepted: accepted ? 1 : 0,
            rejected: accepted ? 0 : 1,
            at: date
        )
    }

    private func noteBulk(layer: RecordingLayer, accepted: Int, rejected: Int, at date: Date) {
        guard accepted > 0 || rejected > 0 else { return }

        let raw = layer.rawValue
        var descriptor = FetchDescriptor<RecordingStat>(
            predicate: #Predicate { $0.layerRawValue == raw }
        )
        descriptor.fetchLimit = 1

        let stat: RecordingStat
        if let existing = try? context.fetch(descriptor).first {
            stat = existing
        } else {
            stat = RecordingStat(layer: layer)
            context.insert(stat)
        }

        stat.lastFiredAt = date
        stat.accepted += accepted
        stat.rejected += rejected
        if accepted > 0 { stat.lastAcceptedAt = date }
    }

    private static func loadLastAccepted(from context: ModelContext) -> AcceptedPoint? {
        var descriptor = FetchDescriptor<LocationSample>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first else { return nil }
        return AcceptedPoint(
            timestamp: latest.timestamp,
            latitude: latest.latitude,
            longitude: latest.longitude
        )
    }
}
