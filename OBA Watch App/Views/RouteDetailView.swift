import SwiftUI
import MapKit
import OBASharedCore

struct RouteDetailView: View {
    let route: OBARoute

    @StateObject private var viewModel: RouteDetailViewModel

    init(route: OBARoute) {
        self.route = route
        _viewModel = StateObject(wrappedValue: RouteDetailViewModel(
            apiClient: WatchAppState.shared.apiClient,
            routeID: route.id
        ))
    }

    var body: some View {
        List {
            if !viewModel.shapeCoordinates.isEmpty {
                RouteShapeMapView(coordinates: viewModel.shapeCoordinates)
                    .frame(height: 120)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    if let short = route.shortName, !short.isEmpty {
                        Text(short)
                            .font(.system(size: 22, weight: .bold))
                    }
                    if let long = route.longName, !long.isEmpty {
                        Text(long)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                    }
                    if let agency = route.agencyName, !agency.isEmpty {
                        Text(agency)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            } else if !viewModel.directions.isEmpty {
                ForEach(viewModel.directions, id: \.id) { direction in
                    Section(direction.name ?? "Direction") {
                        ForEach(direction.stops, id: \.id) { stop in
                            NavigationLink {
                                StopArrivalsView(stopID: stop.id, stopName: stop.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    if let code = stop.code, !code.isEmpty {
                                        Text("Stop \(code)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(route.shortName ?? "Route")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }
}

struct RouteShapeMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let mapStyle: MapStyle

    @State private var region: MKCoordinateRegion

    init(coordinates: [CLLocationCoordinate2D], mapStyle: MapStyle = .standard) {
        self.coordinates = coordinates
        self.mapStyle = mapStyle

        let center: CLLocationCoordinate2D
        if let first = coordinates.first {
            center = first
        } else {
            center = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        _region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
    }

    var body: some View {
        // Approximate the shape by placing small markers along the polyline.
        let sampleCoordinates = stride(from: 0, to: coordinates.count, by: max(1, coordinates.count / 20)).map { coordinates[$0] }
        let points = sampleCoordinates.map { RouteShapePoint(coordinate: $0) }

        Map(coordinateRegion: $region, annotationItems: points) { point in
            MapMarker(coordinate: point.coordinate, tint: .green)
        }
    }
}

private struct RouteShapePoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
