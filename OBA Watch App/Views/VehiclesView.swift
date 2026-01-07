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
            apiClientProvider: { WatchAppState.shared.apiClient },
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
                        Text("No vehicles currently in service")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                .listRowBackground(Color.clear)
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

    var body: some View {
        Map {
            UserAnnotation()
            
            ForEach(trips) { trip in
                if let lat = trip.latitude, let lon = trip.longitude {
                    Marker(trip.routeShortName ?? "Bus", systemImage: "bus", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                        .tint(.blue)
                }
            }
        }
        .mapStyle(mapStyle)
    }
}

struct VehiclePin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let orientation: Double?
    let routeShortName: String?
}
