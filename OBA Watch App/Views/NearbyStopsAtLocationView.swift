import SwiftUI
import CoreLocation
import MapKit
import OBAKitCore

/// Shows nearby stops for a fixed coordinate selected from address search,
/// mirroring the iOS "Nearby Stops" sheet but in a simplified watch layout.
struct NearbyStopsAtLocationView: View {
    @EnvironmentObject var appState: WatchAppState
    let title: String
    let coordinate: CLLocationCoordinate2D

    @StateObject private var viewModel: NearbyStopsViewModel
    @State private var searchText: String = ""

    init(title: String, coordinate: CLLocationCoordinate2D) {
        self.title = title
        self.coordinate = coordinate
        _viewModel = StateObject(wrappedValue: NearbyStopsViewModel(
            apiClientProvider: { WatchAppState.shared.apiClient },
            locationProvider: {
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
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
                } else if viewModel.stops.isEmpty {
                    emptyStateView
                } else {
                    NearbyStopsListView(
                        stops: viewModel.stops,
                        currentLocation: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                        mapStyle: appState.mapStyle,
                        routeSummaryByStopID: nil,
                        searchText: $searchText
                    )
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // TODO: Implement DeepLinkSyncManager in PR3/PR4
                        // DeepLinkSyncManager.shared.planTripOnPhone(
                        //     originLat: coordinate.latitude,
                        //     originLon: coordinate.longitude,
                        //     destLat: nil,
                        //     destLon: nil
                        // )
                    } label: {
                        Label(OBALoc("common.plan_on_phone", value: "Plan on Phone", comment: "Action to plan trip on phone"), systemImage: "figure.walk")
                    }
                }
            }
            .refreshable {
                await viewModel.loadNearbyStops()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(OBALoc("nearby_stops.no_stops", value: "No Stops Found", comment: "Empty state title for nearby stops"))
                .font(.headline)
            Text(viewModel.locationStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
