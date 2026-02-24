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
                    NavigationLink {
                        TripDetailsView(
                            tripID: vehicle.tripID ?? "",
                            vehicleID: vehicle.id,
                            routeShortName: vehicle.routeShortName,
                            headsign: vehicle.tripHeadsign,
                            initialTrip: vehicle.toTripForLocation()
                        )
                    } label: {
                        VehicleRow(
                            vehicleID: vehicle.id,
                            routeShortName: vehicle.routeShortName,
                            tripHeadsign: vehicle.tripHeadsign,
                            lastUpdateTime: vehicle.lastUpdateTime,
                            status: vehicle.status,
                            phase: vehicle.phase,
                            tripID: vehicle.tripID,
                            latitude: vehicle.latitude,
                            longitude: vehicle.longitude
                        )
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.12))
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            } else if !viewModel.nearbyVehicles.isEmpty {
                Section {
                    ForEach(viewModel.nearbyVehicles) { trip in
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
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
            }
        }
        .navigationTitle("Search")
        .onAppear {
            viewModel.performSearch()
        }
    }

    private func vehicleStatus(_ trip: OBATripForLocation) -> String? {
        if let deviation = trip.scheduleDeviation {
            let minutes = abs(deviation) / 60
            if deviation == 0 { return "On time" }
            let label = deviation > 0 ? "late" : "early"
            return "\(minutes)m \(label)"
        } else if trip.predicted == true || trip.lastUpdateTime != nil {
            return "On time"
        } else if trip.predicted == false {
            return "Scheduled"
        }
        return nil
    }
}
