import SwiftUI
import MapKit
import OBAKitCore

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
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    if let short = route.shortName, !short.isEmpty {
                        Text(short)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    if let long = route.longName, !long.isEmpty {
                        Text(long)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                    }
                    if let agency = route.agencyName, !agency.isEmpty {
                        Text(agency)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
            )

            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
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
                                HStack(spacing: 12) {
                                    Image(systemName: "signpost.right.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 30, height: 30)
                                        .background(Color.green.gradient)
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stop.name)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        
                                        if let code = stop.code, !code.isEmpty {
                                            Text("Stop \(code)")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.1))
                            )
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

    @State private var mapPosition: MapCameraPosition

    init(coordinates: [CLLocationCoordinate2D], mapStyle: MapStyle = .standard) {
        self.coordinates = coordinates
        self.mapStyle = mapStyle

        let center: CLLocationCoordinate2D
        if let first = coordinates.first {
            center = first
        } else {
            center = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        _mapPosition = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )))
    }

    var body: some View {
        Map(position: $mapPosition) {
            if !coordinates.isEmpty {
                MapPolyline(coordinates: coordinates)
                    .stroke(.green, lineWidth: 3)
            }
            
            // Show a few icons along the route to indicate vehicle type
            let sampleCount = 3
            let step = max(1, coordinates.count / (sampleCount + 1))
            let sampleIndices = (1...sampleCount).map { $0 * step }.filter { $0 < coordinates.count }
            
            ForEach(sampleIndices, id: \.self) { index in
                Annotation("", coordinate: coordinates[index]) {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 20, height: 20)
                            .shadow(radius: 2)
                        
                        Image(systemName: "bus.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .mapStyle(mapStyle)
    }
}

private struct RouteShapePoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
