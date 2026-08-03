import Foundation

/// 過去データの取り込み(仕様 §8 / Issue #6)。
///
/// 解析は純粋関数として SwiftData から切り離す。取り込んだ点は
/// `LocationStore.ingestHistorical` で §3.5 のパイプラインを通す。
enum LocationImporter {
    enum ImportError: LocalizedError, Equatable {
        case unsupportedFormat(String)
        case noPointsFound

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let name):
                return "\(name) は対応していない形式です。Googleタイムライン JSON / GPX / CSV に対応しています。"
            case .noPointsFound:
                return "位置情報が1件も見つかりませんでした。"
            }
        }
    }

    /// 精度が記録されていない形式のときに使う値。
    ///
    /// `RecordingPolicy.maxHorizontalAccuracy` と同値にしてあるので、
    /// 「採用できる中で最も悪い」扱いになる。閾値を下げた場合は自動的に弾かれる。
    static let assumedAccuracy = RecordingPolicy.maxHorizontalAccuracy

    static func parse(data: Data, fileName: String) throws -> [LocationPayload] {
        let payloads: [LocationPayload]

        switch fileName.lowercased() {
        case let name where name.hasSuffix(".json"):
            payloads = parseGoogleTimeline(data)
        case let name where name.hasSuffix(".gpx") || name.hasSuffix(".xml"):
            payloads = parseGPX(data)
        case let name where name.hasSuffix(".csv") || name.hasSuffix(".txt"):
            payloads = parseCSV(data)
        default:
            // 拡張子が当てにならない場合は中身で判定する。
            if let sniffed = sniff(data) {
                payloads = sniffed
            } else {
                throw ImportError.unsupportedFormat(fileName)
            }
        }

        guard !payloads.isEmpty else { throw ImportError.noPointsFound }
        return payloads
    }

    private static func sniff(_ data: Data) -> [LocationPayload]? {
        let head = String(decoding: data.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("{") || head.hasPrefix("[") {
            let parsed = parseGoogleTimeline(data)
            return parsed.isEmpty ? nil : parsed
        }
        if head.hasPrefix("<") {
            let parsed = parseGPX(data)
            return parsed.isEmpty ? nil : parsed
        }
        let parsed = parseCSV(data)
        return parsed.isEmpty ? nil : parsed
    }

    // MARK: - Google タイムライン JSON

    /// 旧形式 (`latitudeE7` / `longitudeE7`) と新形式 (`"35.6°, 139.7°"` 文字列) の
    /// 両方に対応する。構造が版で変わるため、キーを決め打ちせず再帰的に走査する。
    static func parseGoogleTimeline(_ data: Data) -> [LocationPayload] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var payloads: [LocationPayload] = []
        walk(root, into: &payloads)
        return payloads
    }

    private static func walk(_ node: Any, into payloads: inout [LocationPayload]) {
        if let array = node as? [Any] {
            for element in array { walk(element, into: &payloads) }
            return
        }
        guard let dict = node as? [String: Any] else { return }

        if let coordinate = coordinate(in: dict), let timestamp = timestamp(in: dict) {
            let accuracy = (dict["accuracy"] as? Double)
                ?? (dict["accuracy"] as? Int).map(Double.init)
                ?? assumedAccuracy
            payloads.append(
                make(
                    timestamp: timestamp,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    accuracy: accuracy
                )
            )
        }

        for value in dict.values { walk(value, into: &payloads) }
    }

    private static func coordinate(in dict: [String: Any]) -> (latitude: Double, longitude: Double)? {
        if let latE7 = intValue(dict["latitudeE7"]), let lonE7 = intValue(dict["longitudeE7"]) {
            return (Double(latE7) / 1e7, Double(lonE7) / 1e7)
        }
        for key in ["point", "latLng", "location", "placeLocation"] {
            if let text = dict[key] as? String, let parsed = parseDegreePair(text) {
                return parsed
            }
        }
        return nil
    }

    /// `"35.6812°, 139.7671°"` 形式。度記号や空白の有無は版によって揺れる。
    static func parseDegreePair(_ text: String) -> (latitude: Double, longitude: Double)? {
        let cleaned = text.replacingOccurrences(of: "°", with: "")
        let parts = cleaned.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              abs(latitude) <= 90, abs(longitude) <= 180
        else { return nil }
        return (latitude, longitude)
    }

    private static func timestamp(in dict: [String: Any]) -> Date? {
        for key in ["timestamp", "time", "startTime"] {
            if let text = dict[key] as? String, let date = parseDate(text) { return date }
        }
        // 旧形式はミリ秒のエポックを文字列で持つ。
        for key in ["timestampMs", "startTimestampMs"] {
            if let milliseconds = intValue(dict[key]) {
                return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
            }
        }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let value = any as? Double { return Int(value) }
        if let text = any as? String { return Int(text) }
        return nil
    }

    // MARK: - GPX

    static func parseGPX(_ data: Data) -> [LocationPayload] {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.payloads
    }

    // MARK: - CSV

    /// `timestamp,lat,lng,accuracy,source`。ExportService の出力を読み戻せる。
    /// 壊れた行は黙って飛ばす。
    static func parseCSV(_ data: Data) -> [LocationPayload] {
        let text = String(decoding: data, as: UTF8.self)
        var payloads: [LocationPayload] = []

        for line in text.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count >= 3 else { continue }

            // ExportService の出力は id が先頭にあるため、両方の並びを受ける。
            let offset = parseDate(columns[0]) != nil ? 0 : 1
            guard columns.count > offset + 2,
                  let timestamp = parseDate(columns[offset]),
                  let latitude = Double(columns[offset + 1]),
                  let longitude = Double(columns[offset + 2])
            else { continue }

            let accuracy = columns.count > offset + 3
                ? Double(columns[offset + 3]) ?? assumedAccuracy
                : assumedAccuracy

            payloads.append(
                make(
                    timestamp: timestamp,
                    latitude: latitude,
                    longitude: longitude,
                    accuracy: accuracy
                )
            )
        }
        return payloads
    }

    // MARK: - 共通

    static func make(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        accuracy: Double
    ) -> LocationPayload {
        LocationPayload(
            id: LocationPayload.stableID(
                timestamp: timestamp,
                latitude: latitude,
                longitude: longitude,
                source: .iPhone
            ),
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            speed: -1,
            course: -1,
            source: .iPhone
        )
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return isoFractional.date(from: trimmed) ?? iso.date(from: trimmed)
    }
}

/// `trkpt` / `wpt` / `rtept` を拾う。`<time>` が無い点は捨てる。
private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    private(set) var payloads: [LocationPayload] = []

    private var latitude: Double?
    private var longitude: Double?
    private var timeText = ""
    private var readingTime = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "trkpt", "wpt", "rtept":
            latitude = attributeDict["lat"].flatMap(Double.init)
            longitude = attributeDict["lon"].flatMap(Double.init)
            timeText = ""
        case "time":
            readingTime = true
            timeText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingTime { timeText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "time":
            readingTime = false
        case "trkpt", "wpt", "rtept":
            defer {
                latitude = nil
                longitude = nil
                timeText = ""
            }
            guard let latitude, let longitude,
                  let timestamp = LocationImporter.parseDate(timeText)
            else { return }
            payloads.append(
                LocationImporter.make(
                    timestamp: timestamp,
                    latitude: latitude,
                    longitude: longitude,
                    accuracy: LocationImporter.assumedAccuracy
                )
            )
        default:
            break
        }
    }
}
