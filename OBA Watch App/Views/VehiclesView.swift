import SwiftUI
import MapKit
import CoreLocation
import OBASharedCore

struct VehiclesView: View {
    @EnvironmentObject private var appState: WatchAppState
    @StateObject private var viewModel: VehiclesViewModel
    @State private var useStandardMapStyle = true
    init() {
        _viewModel = StateObject(wrappedValue: VehiclesViewModel(
            apiClient: WatchAppState.shared.apiClient,
            locationProvider: { WatchAppState.shared.currentLocation }
        ))
    }
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    ErrorView(message: error)
                } else if viewModel.trips.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bus")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Vehicles Found")
                            .font(.headline)
                    }
                    .padding()
                } else {
                    listView
                }
            }
            .navigationTitle("Vehicles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        useStandardMapStyle.toggle()
                    } label: {
                        Image(systemName: useStandardMapStyle ? "map" : "globe")
                    }
                }
            }
            .refreshable {
                await viewModel.loadNearbyVehicles()
            }
        }
        .task {
            await viewModel.loadNearbyVehicles()
        }
    }
    private var listView: some View {
        let limited = Array(viewModel.trips.prefix(30))
        return List {
            if !limited.isEmpty {
                VehiclesMapView(
                    trips: limited,
                    currentLocation: appState.currentLocation,
                    mapStyle: useStandardMapStyle ? .standard : .imagery
                )
                .frame(height: 140)
            }
            Section("Nearby Vehicles") {
                ForEach(limited) { trip in
                    NavigationLink {
                        TripDetailsView(
                            tripID: trip.id,
                            vehicleID: trip.vehicleID,
                            routeShortName: trip.routeShortName,
                            headsign: trip.tripHeadsign
                        )
                    } label: {
                        HStack {
                            Text(trip.routeShortName ?? trip.vehicleID)
                                .font(.headline)
                            Spacer()
                            if let t = trip.lastUpdateTime {
                                Text(DateFormatterHelper.contextualDateTimeString(t))
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

struct VehiclesMapView: View {
    let trips: [OBATripForLocation]
    let currentLocation: CLLocation?
    var mapStyle: MapStyle = .standard
    @State private var region: MKCoordinateRegion
    init(trips: [OBATripForLocation], currentLocation: CLLocation?, mapStyle: MapStyle = .standard) {
        self.trips = trips
        self.currentLocation = currentLocation
        self.mapStyle = mapStyle
        let center: CLLocationCoordinate2D
        if let loc = currentLocation?.coordinate {
            center = loc
        } else if let first = trips.first {
            center = CLLocationCoordinate2D(latitude: first.latitude ?? 0, longitude: first.longitude ?? 0)
        } else {
            center = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        _region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        ))
    }
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: trips.compactMap { trip -> VehiclePin? in
            guard let lat = trip.latitude, let lon = trip.longitude else { return nil }
            return VehiclePin(id: trip.id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }) { pin in
            MapMarker(coordinate: pin.coordinate, tint: .blue)
        }
        .mapStyle(mapStyle)
    }
}

struct VehiclePin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
}
