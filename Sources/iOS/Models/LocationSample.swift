import Foundation
import SwiftData

@Model
final class LocationSample {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var speed: Double
    var course: Double
    var sourceRawValue: String
    var gridKey: String
    /// どの経路で届いたか。書き出しにも列として出す。
    var layerRawValue: String = RecordingLayer.unknown.rawValue

    init(payload: LocationPayload, gridKey: String, layer: RecordingLayer = .unknown) {
        layerRawValue = layer.rawValue
        id = payload.id
        timestamp = payload.timestamp
        latitude = payload.latitude
        longitude = payload.longitude
        altitude = payload.altitude
        horizontalAccuracy = payload.horizontalAccuracy
        verticalAccuracy = payload.verticalAccuracy
        speed = payload.speed
        course = payload.course
        sourceRawValue = payload.source.rawValue
        self.gridKey = gridKey
    }

    var source: LocationSource {
        LocationSource(rawValue: sourceRawValue) ?? .iPhone
    }

    var layer: RecordingLayer {
        RecordingLayer(rawValue: layerRawValue) ?? .unknown
    }
}
