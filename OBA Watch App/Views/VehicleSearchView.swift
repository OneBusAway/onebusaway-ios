import SwiftUI
import OBAKitCore

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
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    TextField("Vehicle ID", text: $viewModel.query)
                        .font(.system(size: 16))
                        .padding(.vertical, 8)
                        .onSubmit { viewModel.performSearch() }
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.15))
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
            } else if let vehicle = viewModel.vehicle {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.purple.gradient)
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Vehicle \(vehicle.id)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                if let status = vehicle.status, !status.isEmpty {
                                    Text(status)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        if let phase = vehicle.phase, !phase.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("Phase: \(phase)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let tripID = vehicle.tripID, !tripID.isEmpty {
                            NavigationLink {
                                TripDetailsView(tripID: tripID, vehicleID: vehicle.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "map.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.blue)
                                    Text("Trip: \(tripID)")
                                        .font(.system(size: 12))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        
                        if let lastUpdate = vehicle.lastUpdateTime {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("Updated: \(DateFormatterHelper.contextualDateTimeString(lastUpdate))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let lat = vehicle.latitude, let lon = vehicle.longitude {
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.4f, %.4f", lat, lon))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                )
            } else if !viewModel.nearbyVehicles.isEmpty {
                Section {
                    ForEach(viewModel.nearbyVehicles) { trip in
                        NavigationLink {
                            TripDetailsView(
                                tripID: trip.id,
                                vehicleID: trip.vehicleID,
                                routeShortName: trip.routeShortName,
                                headsign: trip.tripHeadsign
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "car.2.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.purple.gradient)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(trip.routeShortName ?? trip.vehicleID)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        if let orientation = trip.orientation {
                                            Image(systemName: "arrow.up")
                                                .rotationEffect(.degrees(orientation))
                                                .font(.system(size: 10))
                                        }
                                    }
                                    
                                    if let headsign = trip.tripHeadsign {
                                        Text(headsign)
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
        .navigationTitle("Vehicle")
        .onAppear {
            viewModel.performSearch()
        }
    }
}
