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
    @State private var infoMessage: String?

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
                            WatchFeedbackGenerator.shared.error()
                            infoMessage = OBALoc("deeplink.failure", value: "Unable to contact iPhone. Make sure your devices are connected.", comment: "Deep link failure")
                        }
                    } label: {
                        Label(OBALoc("common.plan_on_phone", value: "Plan on Phone", comment: "Action to plan trip on phone"), systemImage: "figure.walk")
                    }
                }
            }
        } emptyState: {
            emptyStateView
        }
        .alert(OBALoc("common.info", value: "Info", comment: "Alert title for information"), isPresented: Binding(
            get: { infoMessage != nil },
            set: { newValue in
                if !newValue { infoMessage = nil }
            }
        )) {
            Button(OBALoc("common.ok", value: "OK", comment: "OK button"), role: .cancel) { }
        } message: {
            Text(infoMessage ?? "")
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            systemImage: "location.slash",
            title: OBALoc("nearby_stops.no_stops", value: "No Stops Found", comment: "Empty state title for nearby stops"),
            message: viewModel.locationStatus
        )
    }
}
