import Foundation

struct ExportService {
    static func writeGeoJSON(samples: [LocationSample]) throws -> URL {
        let features: [[String: Any]] = samples.map { sample in
            [
                "type": "Feature",
                "geometry": [
                    "type": "Point",
                    "coordinates": [sample.longitude, sample.latitude]
                ],
                "properties": [
                    "id": sample.id.uuidString,
                    "timestamp": ISO8601DateFormatter().string(from: sample.timestamp),
                    "source": sample.sourceRawValue,
                    "horizontalAccuracy": sample.horizontalAccuracy
                ]
            ]
        }
        let object: [String: Any] = ["type": "FeatureCollection", "features": features]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("unvisited-location-history.geojson")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func writeCSV(samples: [LocationSample]) throws -> URL {
        var rows = [
            "id,timestamp,latitude,longitude,altitude,horizontal_accuracy,speed,course,source,layer"
        ]
        let formatter = ISO8601DateFormatter()
        rows.append(contentsOf: samples.map { sample in
            [
                sample.id.uuidString,
                formatter.string(from: sample.timestamp),
                String(sample.latitude),
                String(sample.longitude),
                String(sample.altitude),
                String(sample.horizontalAccuracy),
                String(sample.speed),
                String(sample.course),
                sample.sourceRawValue,
                sample.layerRawValue
            ].joined(separator: ",")
        })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("unvisited-location-history.csv")
        try rows.joined(separator: "\n").data(using: .utf8)?.write(
            to: url,
            options: [.atomic, .completeFileProtection]
        )
        return url
    }
}
