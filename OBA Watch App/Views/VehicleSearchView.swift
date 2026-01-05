import SwiftUI
import OBASharedCore

struct VehicleSearchView: View {
    @StateObject private var viewModel: VehicleSearchViewModel

    init(initialQuery: String) {
        _viewModel = StateObject(wrappedValue: VehicleSearchViewModel(
            initialQuery: initialQuery,
            apiClient: WatchAppState.shared.apiClient,
            locationProvider: { WatchAppState.shared.currentLocation }
        ))
    }

    var body: some View {
        List {
            Section {
                TextField("Vehicle ID", text: $viewModel.query)
                    .onSubmit { viewModel.performSearch() }
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
            } else if let vehicle = viewModel.vehicle {
                Section("Vehicle") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vehicle.id)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if let status = vehicle.status, !status.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Status: \(status)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let phase = vehicle.phase, !phase.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Phase: \(phase)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let tripID = vehicle.tripID {
                            NavigationLink {
                                TripDetailsView(tripID: tripID, vehicleID: vehicle.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "map")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("Trip: \(tripID)")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if let lastUpdate = vehicle.lastUpdateTime {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Updated: \(DateFormatterHelper.contextualDateTimeString(lastUpdate))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let lat = vehicle.latitude, let lon = vehicle.longitude {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.4f, %.4f", lat, lon))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else if !viewModel.nearbyVehicles.isEmpty {
                Section("Nearby Vehicles") {
                    ForEach(viewModel.nearbyVehicles) { trip in
                        NavigationLink {
                            TripDetailsView(
                                tripID: trip.id,
                                vehicleID: trip.vehicleID,
                                routeShortName: trip.routeShortName,
                                headsign: trip.tripHeadsign
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(trip.routeShortName ?? trip.vehicleID)
                                        .font(.headline)
                                    Spacer()
                                    if let orientation = trip.orientation {
                                        Image(systemName: "arrow.up")
                                            .rotationEffect(.degrees(orientation))
                                            .font(.caption2)
                                    }
                                }
                                
                                if let headsign = trip.tripHeadsign {
                                    Text(headsign)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Vehicle")
        .onAppear {
            viewModel.performSearch()
        }
    }
}
