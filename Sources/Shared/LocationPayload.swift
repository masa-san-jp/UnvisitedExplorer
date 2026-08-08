import CryptoKit
import Foundation

public enum LocationSource: String, Codable, Sendable {
    case iPhone
    case appleWatch
}

public struct LocationPayload: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let horizontalAccuracy: Double
    public let verticalAccuracy: Double
    public let speed: Double
    public let course: Double
    public let source: LocationSource

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        speed: Double,
        course: Double,
        source: LocationSource
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.source = source
    }

    /// 内容から決まる安定した ID。
    ///
    /// インポートは `id` を都度 `UUID()` で振ると、同じファイルを2回読んだときに
    /// 全件が別レコードとして入ってしまう。取り込み経路ではこれを使い、
    /// 同一地点・同一時刻の点が再投入されても既存 ID と衝突して弾かれるようにする。
    public static func stableID(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        source: LocationSource
    ) -> UUID {
        let seed = [
            source.rawValue,
            String(Int(timestamp.timeIntervalSince1970.rounded())),
            String(format: "%.6f", latitude),
            String(format: "%.6f", longitude)
        ].joined(separator: "|")

        let digest = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        var raw = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &raw) { buffer in
            for (index, byte) in digest.enumerated() { buffer[index] = byte }
        }
        return UUID(uuid: raw)
    }
}
