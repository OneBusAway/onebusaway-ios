//
//  MapViewController+TripPlanner.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import FloatingPanel
import MapKit
import OBAKitCore
import OTPKit
import SwiftUI
import UIKit

/// Trip planner presentation. An extension rather than more of `MapViewController`
/// because presenting one feature is a separate concern from the map state that
/// class holds — not because of a lint limit. `type_body_length` reports nothing
/// on `MapViewController` today; only `file_length` is suppressed there.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1303
extension MapViewController {

    func showTripPlannerMapView() {
        tripPlannerMapView.mapType = mapRegionManager.mapView.mapType

        tripPlannerMapView.isHidden = false

        UIView.animate(withDuration: 0.3) {
            self.mapRegionManager.mapView.alpha = 0
            self.tripPlannerMapView.alpha = 1
        } completion: { _ in
            self.mapRegionManager.mapView.isHidden = true
        }
    }

    func hideTripPlannerMapView() {
        mapRegionManager.mapView.mapType = tripPlannerMapView.mapType
        mapRegionManager.mapView.region = tripPlannerMapView.region

        mapRegionManager.mapView.isHidden = false

        UIView.animate(withDuration: 0.3) {
            self.mapRegionManager.mapView.alpha = 1
            self.tripPlannerMapView.alpha = 0
        } completion: { _ in
            self.tripPlannerMapView.isHidden = true
        }
    }

    func buildTripPlanner(region: Region) -> TripPlanner? {
        // GraphQL (OTP 2.x) is the preferred trip-planning API whenever the region
        // provides it; OTP 1.x REST is the fallback. Only the GraphQL service can
        // support vehicle rental features.
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

        var enabledModes: [TransportMode] = [.transit, .walk, .bike, .car]
        if region.isBikeshareEnabled {
            // The capability filter in OTPKit hides these again if the service
            // can't actually plan rental trips (e.g. the REST fallback).
            enabledModes.append(contentsOf: [.transitBikeRental, .bikeRental])
        }

        let searchRect = application.currentRegion?.serviceRect ?? mapRegionManager.mapView.visibleMapRect

        let config = OTPConfiguration(
            otpServerURL: serverURL,
            enabledTransportModes: enabledModes,
            themeConfiguration: .init(
                primaryColor: Color(uiColor: ThemeColors().brand)
            ),
            searchRegion: MKCoordinateRegion(searchRect)
        )

        let mapViewProvider = MKMapViewAdapter(mapView: tripPlannerMapView)

        let tripPlanner = TripPlanner(
            otpConfig: config,
            apiService: apiService,
            mapProvider: mapViewProvider,
            notificationCenter: application.notificationCenter
        )

        return tripPlanner
    }

    /// Presents the trip planner.
    /// - Parameters:
    ///   - origin: Optional prefilled origin. When set, current location is not
    ///     used as origin — stop-page "Directions from Here" relies on that.
    ///   - destination: Optional prefilled destination.
    ///   - viaPoint: Optional coordinate every planned trip must pass through — used by
    ///     "Plan a trip using this bike" with the vehicle's location.
    ///   - preselectedMode: Optional transport mode to preselect, e.g. `.transitBikeRental`.
    func showTripPlanner(
        origin: MKMapItem? = nil,
        destination: MKMapItem? = nil,
        viaPoint: CLLocationCoordinate2D? = nil,
        preselectedMode: TransportMode? = nil
    ) {
        guard let currentRegion = application.regionsService.currentRegion,
              currentRegion.supportsOTP,
              application.userDataStore.isTripPlanningEnabled(for: currentRegion) else {
            return
        }

        let originLocation = TripPlannerEndpoints.origin(
            explicit: origin,
            currentLocation: application.locationService.currentLocation
        )
        let destinationLocation = TripPlannerEndpoints.destination(from: destination)

        guard let tripPlanner = buildTripPlanner(region: currentRegion) else { return }

        subscribeToTripPlannerNotifications()

        let tripPlannerView = tripPlanner.createTripPlannerView(
            origin: originLocation,
            destination: destinationLocation,
            viaPoint: viaPoint,
            transportMode: preselectedMode
        ) { [weak self] in
            guard let self else { return }
            self.dismissTripPlannerController()
        }

        self.floatingPanel.move(to: .tip, animated: true)

        let hostingController = UIHostingController(rootView: tripPlannerView)
        hostingController.view.backgroundColor = .clear

        let semiModal = createSemiModalPanel(childController: hostingController)
        semiModal.addPanel(toParent: self)
        self.semiModalTripPlannerController = semiModal
        self.tripPlanner = tripPlanner
        self.tripPlannerHostingController = hostingController
    }

    func dismissTripPlannerController() {
        guard let tripPlannerHostingController else { return }
        dismissModalController(tripPlannerHostingController)

        self.semiModalTripPlannerController = nil
        self.tripPlannerHostingController = nil
        self.tripPlanner = nil
        hideTripPlannerMapView()

        unsubscribeFromTripPlannerNotifications()
    }

    func subscribeToTripPlannerNotifications() {
        application.notificationCenter.addObserver(self, selector: #selector(itinerariesUpdated), name: Notifications.itinerariesUpdated, object: nil)
        application.notificationCenter.addObserver(self, selector: #selector(tripStarted), name: Notifications.tripStarted, object: nil)
    }

    func unsubscribeFromTripPlannerNotifications() {
        application.notificationCenter.removeObserver(self, name: Notifications.itinerariesUpdated, object: nil)
        application.notificationCenter.removeObserver(self, name: Notifications.tripStarted, object: nil)
    }

    @objc func itinerariesUpdated(_ note: NSNotification) {
        semiModalTripPlannerController?.move(to: .full, animated: true)
    }

    @objc func tripStarted(_ note: NSNotification) {
        showTripPlannerMapView()

        semiModalTripPlannerController?.move(to: .tip, animated: true)
    }
}
