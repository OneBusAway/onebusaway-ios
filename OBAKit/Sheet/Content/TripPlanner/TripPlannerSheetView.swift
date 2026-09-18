//
//  TripPlannerSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import SwiftUI
import MapKit
import CoreLocation
import OBAKitCore
import OTPKit

// MARK: - TripPlannerObservableWrapper

/// Wraps `OTPKit.TripPlanner` for `@StateObject` use.
///
/// `TripPlanner` owns `TripPlannerViewModel` for its lifetime and is not itself
/// an `ObservableObject`. The sheet holds it in `@StateObject` via this wrapper,
/// so rebuilds of the view don't reconstruct `TripPlanner` mid-flow and reset the
/// rider's trip state.
@MainActor
final class TripPlannerObservableWrapper: ObservableObject {
    let tripPlanner: OTPKit.TripPlanner

    private var didPrefill = false

    init(tripPlanner: OTPKit.TripPlanner) {
        self.tripPlanner = tripPlanner
    }

    /// Applies the route's prefill to the planner, exactly once.
    ///
    /// OTPKit prefills as a side effect of building the view: `createTripPlannerView`
    /// writes `selectTransportMode` and `viaPoint`, and `TripPlannerView.init` writes
    /// `selectedOrigin` / `selectedDestination`. Every one of those is `@Published` on
    /// a view model SwiftUI is already observing, so doing it from `body` mutates
    /// observed state in the middle of a view update — which is what SwiftUI reports as
    /// "Publishing changes from within view updates is not allowed". Calling it from
    /// `.task` instead runs the same writes one turn later, outside the update pass.
    ///
    /// The returned view is discarded: the prefill *is* the side effect, and the view
    /// actually on screen is the unprefilled one `body` built, which renders from the
    /// same view model and so picks these values up as published changes.
    ///
    /// Guarded because `.task` re-runs whenever the view's identity changes, and a
    /// second application would stamp the route's original mode back over whatever the
    /// rider has since chosen.
    func applyPrefillIfNeeded(destination: Location?, viaPoint: CLLocationCoordinate2D?, transportMode: TransportMode?) {
        guard !didPrefill else { return }
        didPrefill = true

        _ = tripPlanner.createTripPlannerView(
            origin: nil,
            destination: destination,
            viaPoint: viaPoint,
            transportMode: transportMode,
            chrome: .embedded,
            onClose: nil
        )
    }
}

// MARK: - TripPlannerSheetView

/// The trip-planning sheet — `AppSheetRoute.tripPlanner`.
///
/// Renders OTPKit's `TripPlanner` with `.embedded` chrome (no close button or title)
/// and provides the panel's own header, so a dismissal close button can clean up both
/// the planner state and the map display model.
///
/// Split in two: this view owns the chrome and the "no OTP URL" case,
/// while `TripPlannerSheetContent` owns the planner. A `@StateObject` can't
/// be created conditionally, and there is no honest planner to build one
/// with when OTP is not configured for the region.
struct TripPlannerSheetView: View {
    let application: Application
    let request: TripPlannerRequest
    let tripPlannerMapDisplayModel: TripPlannerMapDisplayModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(OBALoc(
                    "trip_planner.title",
                    value: "Trip Planner",
                    comment: "Title for the trip planner sheet"
                )))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { dismiss() }
                    }
                }
        }
        .searchSheetBackground()
    }

    @ViewBuilder
    private var content: some View {
        if canBuildPlanner(application: application) {
            TripPlannerSheetContent(
                application: application,
                request: request,
                tripPlannerMapDisplayModel: tripPlannerMapDisplayModel
            )
        } else {
            unavailableStateView
        }
    }

    /// When no OTP server is configured for this region, render an unavailable state
    /// rather than crashing. Follows the pattern used by other sheets when content
    /// cannot be loaded.
    @ViewBuilder
    private var unavailableStateView: some View {
        EmptyStateView(
            title: OBALoc(
                "trip_planner.unavailable.title",
                value: "Trip Planner Not Available",
                comment: "Title shown when trip planning is not available for the current region"
            ),
            description: OBALoc(
                "trip_planner.unavailable.body",
                value: "This region does not support trip planning.",
                comment: "Body text shown when trip planning is not available for the current region"
            ),
            systemImage: AppSymbol.search
        )
    }

    /// Checks whether a planner can be built for the current region.
    private func canBuildPlanner(application: Application) -> Bool {
        guard let region = application.currentRegion,
              region.supportsOTP,
              application.userDataStore.isTripPlanningEnabled(for: region) else {
            return false
        }

        return (region.openTripPlannerGraphQLURL != nil) || (region.openTripPlannerURL != nil)
    }
}

// MARK: - TripPlannerSheetContent

/// The planner UI. Owns `TripPlanner` via `@StateObject` so the parent can decline to
/// build one when OTP is not configured.
private struct TripPlannerSheetContent: View {
    let application: Application
    let request: TripPlannerRequest
    let tripPlannerMapDisplayModel: TripPlannerMapDisplayModel

    @StateObject private var plannerWrapper: TripPlannerObservableWrapper
    @EnvironmentObject private var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    init(
        application: Application,
        request: TripPlannerRequest,
        tripPlannerMapDisplayModel: TripPlannerMapDisplayModel
    ) {
        self.application = application
        self.request = request
        self.tripPlannerMapDisplayModel = tripPlannerMapDisplayModel

        // Built inside the `@StateObject` autoclosure, which SwiftUI evaluates at most
        // once per view lifetime. Hoisting it into a `let` first would construct a
        // `TripPlanner` — and with it a `MapCoordinator` and a `TripPlannerViewModel` —
        // on every re-init of this struct, which SwiftUI performs freely, only to throw
        // all but the first away.
        //
        // Force-unwrapped because the parent renders this only when `canBuildPlanner`
        // has already established the region has an OTP server.
        _plannerWrapper = StateObject(wrappedValue: TripPlannerObservableWrapper(
            tripPlanner: Self.buildTripPlanner(
                application: application,
                tripPlannerMapDisplayModel: tripPlannerMapDisplayModel
            )!
        ))
    }

    var body: some View {
        // Built with no prefill so this pass writes nothing to the planner's view
        // model — see `applyPrefillIfNeeded`, which does the writing from `.task`.
        // Every nil argument is a documented no-op inside OTPKit.
        plannerWrapper.tripPlanner.createTripPlannerView(chrome: .embedded)
            .task {
                plannerWrapper.applyPrefillIfNeeded(
                    destination: mapItemToLocation(request.destination),
                    viaPoint: request.viaPoint,
                    transportMode: request.transportMode
                )
            }
            .onReceive(application.notificationCenter.publisher(for: Notifications.tripStarted)) { _ in
                // The rider picked an itinerary, so OTPKit is presenting its directions
                // sheet on top of this one. Drop to `.medium` to uncover the map the
                // directions describe — a full-height planner underneath would leave the
                // route invisible behind two stacked sheets.
                //
                // The UIKit surface does the same thing one rung lower, moving its panel
                // to `.tip` (`MapViewController+TripPlanner.tripStarted`). The panel stops
                // at `.medium` because its sheets are the app's own navigation, not a
                // dedicated planner screen: collapsing to a sliver would strand the rider
                // with no visible way back.
                coordinator.setStackedDetent(.medium) { route in
                    if case .tripPlanner = route { return true }
                    return false
                }
            }
            .onDisappear {
                cleanupPlanner()
            }
    }

    /// Converts an `MKMapItem` destination to OTPKit's `Location` type.
    ///
    /// Follows the same pattern as `MapViewController.showTripPlanner(_:)`.
    private func mapItemToLocation(_ mapItem: MKMapItem?) -> Location? {
        guard let mapItem else { return nil }
        return Location(
            title: mapItem.name ?? OBALoc(
                "trip_planner.destination.default_title",
                value: "Destination",
                comment: "Default title for a trip planner destination"
            ),
            subTitle: mapItem.placemark.title ?? "",
            latitude: mapItem.placemark.coordinate.latitude,
            longitude: mapItem.placemark.coordinate.longitude
        )
    }

    /// Builds an OTPKit `TripPlanner` for the current region.
    ///
    /// Follows the same pattern as `MapViewController.buildTripPlanner(region:)`,
    /// selecting between GraphQL (OTP 2.x) and REST (OTP 1.x) based on region config.
    ///
    /// Must only be called when the region has been validated to support OTP.
    private static func buildTripPlanner(
        application: Application,
        tripPlannerMapDisplayModel: TripPlannerMapDisplayModel
    ) -> OTPKit.TripPlanner? {
        guard let region = application.currentRegion else {
            return nil
        }

        // GraphQL (OTP 2.x) is preferred; REST (OTP 1.x) is the fallback.
        let serverURL: URL
        let apiService: OTPKit.APIService
        if let graphQLURL = region.openTripPlannerGraphQLURL {
            serverURL = graphQLURL
            apiService = GraphQLAPIService(baseURL: graphQLURL)
        } else if let restURL = region.openTripPlannerURL {
            serverURL = restURL
            apiService = RestAPIService(baseURL: restURL)
        } else {
            return nil
        }

        // Transport modes: always [.transit, .walk, .bike, .car];
        // append rental modes if region supports bike rental.
        var enabledModes: [TransportMode] = [.transit, .walk, .bike, .car]
        if region.isBikeshareEnabled {
            enabledModes.append(contentsOf: [.transitBikeRental, .bikeRental])
        }

        // Search region from the current region's service rect.
        let searchRegion = MKCoordinateRegion(region.serviceRect)

        let config = OTPConfiguration(
            otpServerURL: serverURL,
            enabledTransportModes: enabledModes,
            themeConfiguration: .init(
                primaryColor: Color(uiColor: ThemeColors().brand)
            ),
            searchRegion: searchRegion
        )

        let tripPlanner = TripPlanner(
            otpConfig: config,
            apiService: apiService,
            mapProvider: tripPlannerMapDisplayModel,
            notificationCenter: application.notificationCenter
        )

        return tripPlanner
    }

    /// Cleans up planner state when the view disappears.
    private func cleanupPlanner() {
        // Reset the planner: clears origin, destination, via point, plan response,
        // selected itinerary, errors, and any routes/annotations drawn on the map.
        plannerWrapper.tripPlanner.reset()

        // Clear the display model: removes any remaining routes and annotations.
        // Task 3 may already call this when the route leaves the stack; if it does,
        // this call is redundant but harmless.
        tripPlannerMapDisplayModel.clear()
    }
}
