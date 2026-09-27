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

/// The planner fallback's state (spec 3.8): the endpoints passed to the
/// planner, used when `tripPlanEmpty` carries none, and the probe in flight.
struct TripPlannerFallbackContext {
    var origin: CLLocationCoordinate2D?
    var destination: CLLocationCoordinate2D?
    var task: Task<Void, Never>?
    /// The planner panel's delegate, held here because the panel keeps it weakly.
    var panelObserver: TripPlannerPanelObserver?
}

/// Tells the map when the trip planner panel changes detent, so the planner
/// card re-lays out against it (and hides at full height). Only the state
/// callback is implemented; the panel keeps its default layout.
final class TripPlannerPanelObserver: NSObject, FloatingPanelControllerDelegate {
    private let onStateChange: () -> Void

    init(onStateChange: @escaping () -> Void) {
        self.onStateChange = onStateChange
    }

    func floatingPanelDidChangeState(_ fpc: FloatingPanelController) {
        onStateChange()
    }
}

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
        tripPlannerFallback.origin = originLocation.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        tripPlannerFallback.destination = destinationLocation.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

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
        let panelObserver = TripPlannerPanelObserver { [weak self] in self?.layoutOnDemandDock() }
        semiModal.delegate = panelObserver
        tripPlannerFallback.panelObserver = panelObserver
        semiModal.addPanel(toParent: self)
        self.semiModalTripPlannerController = semiModal
        self.tripPlanner = tripPlanner
        self.tripPlannerHostingController = hostingController
        updateOnDemandDockContext()
    }

    func dismissTripPlannerController() {
        guard let tripPlannerHostingController else { return }
        dismissModalController(tripPlannerHostingController)

        self.semiModalTripPlannerController = nil
        tripPlannerFallback.panelObserver = nil
        self.tripPlannerHostingController = nil
        self.tripPlanner = nil
        hideTripPlannerMapView()

        tripPlannerFallback.task?.cancel()
        tripPlannerFallback.task = nil
        onDemandProbeController.clearPlanner()
        unsubscribeFromTripPlannerNotifications()
        updateOnDemandDockContext()
    }

    func subscribeToTripPlannerNotifications() {
        application.notificationCenter.addObserver(self, selector: #selector(itinerariesUpdated), name: Notifications.itinerariesUpdated, object: nil)
        application.notificationCenter.addObserver(self, selector: #selector(tripStarted), name: Notifications.tripStarted, object: nil)
        application.notificationCenter.addObserver(self, selector: #selector(tripPlanEmpty), name: Notifications.tripPlanEmpty, object: nil)
    }

    func unsubscribeFromTripPlannerNotifications() {
        application.notificationCenter.removeObserver(self, name: Notifications.itinerariesUpdated, object: nil)
        application.notificationCenter.removeObserver(self, name: Notifications.tripStarted, object: nil)
        application.notificationCenter.removeObserver(self, name: Notifications.tripPlanEmpty, object: nil)
    }

    @objc func itinerariesUpdated(_ note: NSNotification) {
        tripPlannerFallback.task?.cancel()
        onDemandProbeController.clearPlanner()
        layoutOnDemandDock()
        semiModalTripPlannerController?.move(to: .full, animated: true)
    }

    /// R11: the planner came back empty (an OTP error or zero itineraries).
    /// Probe both ends and dock the on-demand options above the planner panel.
    @objc func tripPlanEmpty(_ note: NSNotification) {
        guard let endpoints = TripPlanEmptyEndpoints.resolve(
            userInfo: note.userInfo,
            fallbackOrigin: tripPlannerFallback.origin,
            fallbackDestination: tripPlannerFallback.destination
        ) else { return }

        tripPlannerFallback.task?.cancel()
        tripPlannerFallback.task = Task { [weak self] in
            guard let self, let result = await onDemandProbeController.plannerResult(origin: endpoints.origin, destination: endpoints.destination) else { return }
            guard !Task.isCancelled else { return }
            onDemandProbeController.showPlanner(result)
            // An empty plan also posts `itinerariesUpdated` first, which moves
            // the panel to full height, where the card is hidden.
            if semiModalTripPlannerController?.state == .full {
                semiModalTripPlannerController?.move(to: .half, animated: true)
            }
            layoutOnDemandDock()
        }
    }

    @objc func tripStarted(_ note: NSNotification) {
        showTripPlannerMapView()

        semiModalTripPlannerController?.move(to: .tip, animated: true)
    }
}
