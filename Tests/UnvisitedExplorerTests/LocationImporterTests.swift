import XCTest
@testable import UnvisitedExplorer

final class LocationImporterTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - Google タイムライン (旧形式)

    func testLegacyTimelineWithE7Coordinates() throws {
        let json = """
        {"locations":[
          {"latitudeE7":360620000,"longitudeE7":1396670000,"timestampMs":"1600000000000","accuracy":25},
          {"latitudeE7":360700000,"longitudeE7":1396800000,"timestamp":"2020-09-13T12:40:00Z","accuracy":40}
        ]}
        """
        let payloads = try LocationImporter.parse(data: data(json), fileName: "Records.json")

        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0].latitude, 36.062, accuracy: 0.0001)
        XCTAssertEqual(payloads[0].longitude, 139.667, accuracy: 0.0001)
        XCTAssertEqual(payloads[0].horizontalAccuracy, 25)
        XCTAssertEqual(payloads[0].timestamp, Date(timeIntervalSince1970: 1_600_000_000))
    }

    // MARK: - Google タイムライン (新形式)

    func testModernTimelineWithDegreeStrings() throws {
        let json = """
        {"semanticSegments":[
          {"timelinePath":[
            {"point":"36.0620°, 139.6670°","time":"2024-05-01T09:00:00.000+09:00"}
          ]},
          {"visit":{"topCandidate":{"placeLocation":"35.6812°, 139.7671°"}},
           "startTime":"2024-05-01T10:00:00+09:00"}
        ]}
        """
        let payloads = try LocationImporter.parse(data: data(json), fileName: "location-history.json")

        XCTAssertEqual(payloads.count, 1, "placeLocation は時刻を同じ辞書に持たないため拾わない")
        XCTAssertEqual(payloads[0].latitude, 36.062, accuracy: 0.0001)
        // 精度が無い形式では採用可能な上限を割り当てる。
        XCTAssertEqual(payloads[0].horizontalAccuracy, LocationImporter.assumedAccuracy)
    }

    func testDegreePairParsing() {
        XCTAssertNil(LocationImporter.parseDegreePair("ほげ"))
        XCTAssertNil(LocationImporter.parseDegreePair("91.0°, 0.0°"), "緯度の範囲外")

        let parsed = LocationImporter.parseDegreePair(" 36.0620° ,139.6670 ")
        XCTAssertEqual(parsed?.latitude, 36.062)
        XCTAssertEqual(parsed?.longitude, 139.667)
    }

    // MARK: - GPX

    func testGPXTrackWaypointAndRoutePoints() throws {
        let gpx = """
        <?xml version="1.0"?>
        <gpx version="1.1">
          <wpt lat="36.0620" lon="139.6670"><time>2024-05-01T00:00:00Z</time></wpt>
          <trk><trkseg>
            <trkpt lat="36.0630" lon="139.6680"><time>2024-05-01T00:05:00Z</time></trkpt>
            <trkpt lat="36.0640" lon="139.6690"></trkpt>
          </trkseg></trk>
          <rte><rtept lat="36.0650" lon="139.6700"><time>2024-05-01T00:10:00Z</time></rtept></rte>
        </gpx>
        """
        let payloads = try LocationImporter.parse(data: data(gpx), fileName: "walk.gpx")

        XCTAssertEqual(payloads.count, 3, "time の無い trkpt は捨てる")
        XCTAssertEqual(payloads.map { $0.latitude.rounded(toPlaces: 3) }, [36.062, 36.063, 36.065])
    }

    // MARK: - CSV

    func testCSVRoundTripFromExportFormat() throws {
        // ExportService は id を先頭に出す。
        let csv = """
        id,timestamp,latitude,longitude,altitude,horizontal_accuracy,speed,course,source
        \(UUID().uuidString),2024-05-01T00:00:00Z,36.0620,139.6670,0.0,12.0,-1.0,-1.0,iPhone
        壊れた行
        \(UUID().uuidString),2024-05-01T00:02:00Z,36.0700,139.6800,0.0,20.0,-1.0,-1.0,iPhone
        """
        let payloads = try LocationImporter.parse(data: data(csv), fileName: "history.csv")

        XCTAssertEqual(payloads.count, 2, "ヘッダと壊れた行は飛ばす")
        XCTAssertEqual(payloads[0].horizontalAccuracy, 12)
    }

    func testCSVWithoutLeadingIDColumn() throws {
        let csv = """
        timestamp,lat,lng,accuracy
        2024-05-01T00:00:00Z,36.0620,139.6670,30
        """
        let payloads = try LocationImporter.parse(data: data(csv), fileName: "simple.csv")

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0].horizontalAccuracy, 30)
    }

    // MARK: - 形式判定と異常系

    func testFormatIsSniffedWhenExtensionIsUnhelpful() throws {
        let json = #"{"locations":[{"latitudeE7":360620000,"longitudeE7":1396670000,"timestampMs":"1600000000000"}]}"#
        let payloads = try LocationImporter.parse(data: data(json), fileName: "download")
        XCTAssertEqual(payloads.count, 1)
    }

    func testEmptyInputIsReportedRatherThanSilentlySucceeding() {
        XCTAssertThrowsError(
            try LocationImporter.parse(data: data("{\"locations\":[]}"), fileName: "empty.json")
        ) { error in
            XCTAssertEqual(error as? LocationImporter.ImportError, .noPointsFound)
        }
    }

    // MARK: - 再取り込み

    /// 同じファイルを2回読んでも重複しないよう、ID は内容から決まる必要がある。
    func testIdentifiersAreStableAcrossParses() throws {
        let gpx = """
        <gpx><trkpt lat="36.0620" lon="139.6670"><time>2024-05-01T00:00:00Z</time></trkpt></gpx>
        """
        let first = try LocationImporter.parse(data: data(gpx), fileName: "a.gpx")
        let second = try LocationImporter.parse(data: data(gpx), fileName: "a.gpx")

        XCTAssertEqual(first[0].id, second[0].id)
    }

    func testDifferentPointsGetDifferentIdentifiers() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let a = LocationPayload.stableID(timestamp: base, latitude: 36.062, longitude: 139.667, source: .iPhone)
        let b = LocationPayload.stableID(timestamp: base, latitude: 36.063, longitude: 139.667, source: .iPhone)
        let c = LocationPayload.stableID(timestamp: base.addingTimeInterval(60), latitude: 36.062, longitude: 139.667, source: .iPhone)

        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
