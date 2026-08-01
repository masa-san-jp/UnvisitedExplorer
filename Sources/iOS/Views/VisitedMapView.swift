import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct VisitedMapView: View {
    @EnvironmentObject private var recorder: LocationRecorder
    @Query(sort: \VisitedCell.lastVisitedAt, order: .reverse) private var visitedCells: [VisitedCell]
    @Query(sort: \LocationSample.timestamp, order: .reverse) private var samples: [LocationSample]

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedSuggestion: ExplorationSuggestion?

    private var origin: CLLocationCoordinate2D? {
        recorder.latestLocation?.coordinate ?? samples.first.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var suggestions: [ExplorationSuggestion] {
        guard let origin else { return [] }
        return ExplorationSuggestionEngine.suggestions(
            from: origin,
            visitedKeys: Set(visitedCells.map(\.key))
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, selection: $selectedSuggestion) {
                UserAnnotation()

                ForEach(Array(visitedCells.prefix(1_500))) { cell in
                    MapPolygon(coordinates: cell.polygonCoordinates)
                        .foregroundStyle(.blue.opacity(0.24))
                }

                ForEach(suggestions) { suggestion in
                    Marker(suggestion.title, coordinate: suggestion.cell.center)
                        .tag(suggestion)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                if recorder.authorizationStatus != .authorizedAlways {
                    PermissionCard()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("訪問済み \(visitedCells.count)セル")
                            .font(.headline)
                        Text("推定面積 \(visitedAreaText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let suggestion = suggestions.first {
                        Button("未訪問へ") {
                            openRoute(to: suggestion)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .navigationTitle("未踏マップ")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            recorder.startRecording()
            recenter()
        }
    }

    private var visitedAreaText: String {
        let squareKilometers = Double(visitedCells.count) * pow(GeoGrid.defaultCellSizeMeters, 2) / 1_000_000
        return String(format: "%.2f km²", squareKilometers)
    }

    private func recenter() {
        guard let origin else { return }
        position = .region(
            MKCoordinateRegion(
                center: origin,
                latitudinalMeters: 4_000,
                longitudinalMeters: 4_000
            )
        )
    }

    private func openRoute(to suggestion: ExplorationSuggestion) {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: suggestion.cell.center))
        destination.name = "未訪問エリア"
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}
