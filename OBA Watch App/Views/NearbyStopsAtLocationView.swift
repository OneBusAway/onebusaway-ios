import SwiftUI
import CoreLocation
import MapKit
import OBAKitCore
import WatchKit

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
        NearbyStopsContainerView(
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            hasStops: !viewModel.stops.isEmpty,
            title: title,
            refreshAction: { await viewModel.loadNearbyStops() }
        ) {
            NearbyStopsListView(
                stops: viewModel.stops,
                currentLocation: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                mapStyle: appState.mapStyle,
                routeSummaryByStopID: nil,
                searchText: $searchText
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let ok = DeepLinkSyncManager.shared.planTripOnPhone(
                            originLat: coordinate.latitude,
                            originLon: coordinate.longitude,
                            destLat: nil,
                            destLon: nil
                        )
                        if !ok {
                            WKInterfaceDevice.current().play(.failure)
                        }
                    } label: {
                        Label(OBALoc("common.plan_on_phone", value: "Plan on Phone", comment: "Action to plan trip on phone"), systemImage: "figure.walk")
                    }
                }
            }
        } emptyState: {
            emptyStateView
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
