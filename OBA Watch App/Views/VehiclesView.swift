import SwiftUI
import MapKit
import CoreLocation
import OBAKitCore

struct VehiclesView: View {
    @EnvironmentObject private var appState: WatchAppState
    @StateObject private var viewModel: VehiclesViewModel
    
    init() {
        _viewModel = StateObject(wrappedValue: VehiclesViewModel(
            apiClientProvider: { WatchAppState.shared.apiClient },
            locationProvider: { WatchAppState.shared.effectiveLocation }
        ))
    }
    var body: some View {
        content
            .navigationTitle(OBALoc("vehicles.title", value: "Vehicles", comment: "Vehicles screen title"))
            .refreshable {
                await viewModel.loadNearbyVehicles()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LocationUpdated"))) { _ in
                Task {
                    await viewModel.loadNearbyVehicles()
                }
            }
            .task {
                await viewModel.loadNearbyVehicles()
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            ErrorView(message: error)
        } else if viewModel.trips.isEmpty {
            emptyStateView
        } else {
            listView
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(OBALoc("vehicles.empty.title", value: "No Vehicles Found", comment: "Empty state title"))
                .font(.headline)
            Text(OBALoc("vehicles.empty.subtitle", value: "No vehicles currently in service", comment: "Empty state subtitle"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    private var listView: some View {
        let limited = Array(viewModel.trips.prefix(30))
        return List {
            if !limited.isEmpty {
                VehiclesMapView(
                    trips: limited,
                    currentLocation: appState.effectiveLocation,
                    mapStyle: appState.mapStyle
                )
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(limited) { trip in
                    NavigationLink {
                        TripDetailsView(
                            tripID: trip.id,
                            vehicleID: trip.vehicleID,
                            routeShortName: trip.routeShortName,
                            headsign: trip.tripHeadsign,
                            initialTrip: trip
                        )
                    } label: {
                        VehicleRow(
                            vehicleID: trip.vehicleID,
                            routeShortName: trip.routeShortName,
                            tripHeadsign: trip.tripHeadsign,
                            lastUpdateTime: trip.lastUpdateTime,
                            status: vehicleStatus(trip),
                            phase: nil as String?,
                            tripID: trip.id,
                            latitude: trip.latitude,
                            longitude: trip.longitude
                        )
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.12))
                    )
                }
            } header: {
                Text(OBALoc("vehicles.section.nearby", value: "Nearby Vehicles", comment: "Section header"))
            }
        }
    }
    
    private func vehicleStatus(_ trip: OBATripForLocation) -> String? {
        if let deviation = trip.scheduleDeviation {
            let minutes = abs(deviation) / 60
            if deviation == 0 { return OBALoc("status.on_time", value: "On time", comment: "On time status") }
            let label = deviation > 0 ? OBALoc("status.late", value: "late", comment: "Late status") : OBALoc("status.early", value: "early", comment: "Early status")
            return "\(minutes)m \(label)"
        } else if trip.predicted == true || trip.lastUpdateTime != nil {
            return OBALoc("status.on_time", value: "On time", comment: "On time status")
        } else if trip.predicted == false {
            return OBALoc("status.scheduled", value: "Scheduled", comment: "Scheduled status")
        }
        return nil
    }
}

struct VehiclesMapView: View {
    let trips: [OBATripForLocation]
    let currentLocation: CLLocation?
    let mapStyle: MapStyle

    @State private var position: MapCameraPosition

    init(trips: [OBATripForLocation], currentLocation: CLLocation?, mapStyle: MapStyle) {
        self.trips = trips
        self.currentLocation = currentLocation
        self.mapStyle = mapStyle
        
        if let loc = currentLocation {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            
            ForEach(trips) { trip in
                if let lat = trip.latitude, let lon = trip.longitude {
                    Marker(trip.routeShortName ?? OBALoc("vehicles.marker.bus", value: "Bus", comment: "Vehicle marker title"), systemImage: "bus", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                        .tint(.blue)
                }
            }
        }
        .mapStyle(mapStyle)
        .onChange(of: currentLocation) { _, newLocation in
            if let loc = newLocation {
                position = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    }
}
