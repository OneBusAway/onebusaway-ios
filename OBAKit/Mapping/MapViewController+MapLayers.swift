//
//  MapViewController+MapLayers.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import OTPKit
import SwiftUI
import UIKit

// MARK: - Map Layers

extension MapViewController {

    /// Registers the map's toggleable layers: the stops adapter always, the
    /// rental layers only when the current region is configured for bikeshare.
    /// Called at load and again whenever the region changes.
    func configureMapLayers() {
        if mapRegionManager.mapLayer(id: StopsMapLayer.layerID) == nil {
            mapRegionManager.registerMapLayer(StopsMapLayer(manager: mapRegionManager))
        }

        configureStopRouteFocusLayer()
        configureRentalLayers()
        updateMapLayerBadge()
    }

    /// Registers `StopRouteFocusMapLayer`, rebuilding it with a fresh
    /// `ShapeCache` when the current region has actually changed.
    ///
    /// `CoreApplication.refreshRESTAPIService()` replaces `application.apiService`
    /// on region change. The layer's `ShapeCache` closes over that service
    /// `[weak apiService]`, so a cache built for the previous region either
    /// resolves nil (a `CancellationError`, and no route line ever draws again
    /// until relaunch) or keeps fetching from the old region's server. Shape IDs
    /// are also region-scoped, so a cache carried over from the old region would
    /// answer with the wrong region's shapes even if the service reference were
    /// still valid.
    ///
    /// Gated on the region identifier actually changing, NOT on every call —
    /// `configureMapLayers()` also runs from `updatedRegionsList`, which fires
    /// routinely without the current region changing at all, and would
    /// otherwise tear this layer down (dropping any open presentation) on every
    /// such refresh.
    private func configureStopRouteFocusLayer() {
        let currentRegionIdentifier = application.currentRegionIdentifier
        let isRegisteredForCurrentRegion = mapRegionManager.mapLayer(id: StopRouteFocusMapLayer.layerID) != nil
            && stopRouteFocusLayerRegionIdentifier == currentRegionIdentifier
        guard !isRegisteredForCurrentRegion else { return }

        if let stale = mapRegionManager.mapLayer(id: StopRouteFocusMapLayer.layerID) as? StopRouteFocusMapLayer {
            stale.invalidateShapeCache()
            mapRegionManager.removeMapLayer(id: StopRouteFocusMapLayer.layerID)
        }

        let apiService = application.apiService
        let shapeCache = ShapeCache { [weak apiService] shapeID in
            guard let apiService else { throw CancellationError() }
            return try await apiService.getShape(id: shapeID).entry.points
        }
        mapRegionManager.registerMapLayer(
            StopRouteFocusMapLayer(mapView: mapRegionManager.mapView, shapeCache: shapeCache, formatters: application.formatters)
        )

        // Registered alongside, and torn down on the same region change: the trip
        // layer draws shapes fetched for this region too, and a shape ID from the
        // old region resolves to the wrong line in the new one.
        mapRegionManager.removeMapLayer(id: TripFocusMapLayer.layerID)
        mapRegionManager.registerMapLayer(TripFocusMapLayer(mapView: mapRegionManager.mapView))

        stopRouteFocusLayerRegionIdentifier = currentRegionIdentifier
    }

    private func configureRentalLayers() {
        // Tear down any layers built for a previous region; preferences persist.
        mapRegionManager.removeMapLayer(id: RentalMapLayer.bikesLayerID)
        mapRegionManager.removeMapLayer(id: RentalMapLayer.scootersLayerID)
        rentalLayerCoordinator = nil

        // Region flag = product enablement; the GraphQL service supplies the
        // capability. Whether the server actually works is decided by the first
        // fetch, which can dim the rows at runtime.
        guard let region = application.regionsService.currentRegion,
              region.isBikeshareEnabled,
              let graphQLURL = region.openTripPlannerGraphQLURL else {
            return
        }

        let service = GraphQLAPIService(baseURL: graphQLURL)
        let coordinator = RentalLayerCoordinator(service: service, mapView: mapRegionManager.mapView)
        rentalLayerCoordinator = coordinator

        // Apply a filter chosen in a previous session before the first fetch,
        // rather than one notification late.
        coordinator.setRangeFilter(mapRegionManager.rentalRangeFilter)

        let bikes = RentalMapLayer.bikesLayer(coordinator: coordinator)
        bikes.actionsDelegate = self
        mapRegionManager.registerMapLayer(bikes)

        let scooters = RentalMapLayer.scootersLayer(coordinator: coordinator)
        scooters.actionsDelegate = self
        mapRegionManager.registerMapLayer(scooters)
    }

    /// Presents a layer-owned detail sheet (vehicle detail or cluster list) for
    /// an annotation, when some registered layer claims it.
    /// - Returns: true when a layer presented a detail surface.
    func presentLayerDetail(for annotation: MKAnnotation, in mapView: MKMapView) -> Bool {
        for layer in mapRegionManager.mapLayers {
            guard let controller = layer.detailViewController(for: annotation) else { continue }

            presentMediumSheet(controller)
            mapView.deselectAnnotation(annotation, animated: true)

            if annotation is RentalAnnotation || annotation is MKClusterAnnotation {
                application.analytics?.reportEvent(
                    pageURL: "app://localhost/bikeshare",
                    label: AnalyticsLabels.rentalVehicleSelected,
                    value: annotation is MKClusterAnnotation ? "cluster" : "vehicle"
                )
            }
            return true
        }
        return false
    }

    @objc func mapLayerStateDidChange(_ note: NSNotification) {
        updateMapLayerBadge()
    }

    /// `MapViewController` is the composition root for the rental layers, so it
    /// carries the threshold from the Map sheet's write to the coordinator that
    /// acts on it. `MapRegionManager` stays unaware the coordinator exists.
    @objc func rentalRangeFilterDidChange(_ note: NSNotification) {
        rentalLayerCoordinator?.setRangeFilter(mapRegionManager.rentalRangeFilter)
    }

    func updateMapLayerBadge() {
        let count = mapRegionManager.enabledMapLayerCount
        mapLayerBadge.text = String(count)
        mapLayerBadge.isHidden = count == 0
    }

    // MARK: - Map Sheet

    func presentMapSheet() {
        let model = MapSheetModel(mapRegionManager: mapRegionManager, mapViewModel: viewModel)
        presentMediumSheet(UIHostingController(rootView: MapSheetView(model: model)))
    }

    private func presentMediumSheet(_ controller: UIViewController) {
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    // MARK: - First-Run Layer Nudge

    private static let mapLayersNudgeShownKey = "mapViewController.mapLayersNudgeShown"

    /// The one-time nudge pointing at the basemap button the first time a region
    /// offers rental layers. Not a permanent band, not a recurring tip — shown
    /// once, then never again.
    func showMapLayersNudgeIfNeeded() {
        guard rentalLayerCoordinator != nil,
              !application.userDefaults.bool(forKey: Self.mapLayersNudgeShownKey),
              presentedViewController == nil else {
            return
        }
        application.userDefaults.set(true, forKey: Self.mapLayersNudgeShownKey)

        let nudge = UILabel.autolayoutNew()
        nudge.text = OBALoc("map_controller.layers_nudge", value: "New: bikes and scooters on the map. Tap to explore.", comment: "One-time callout pointing at the basemap button when a region gains rental map layers")
        nudge.font = .preferredFont(forTextStyle: .footnote)
        nudge.textColor = .white
        nudge.numberOfLines = 0
        nudge.textAlignment = .center

        let padded = UIView.autolayoutNew()
        padded.backgroundColor = UIColor.rentalPurple
        padded.layer.cornerRadius = 10
        padded.layer.masksToBounds = true
        padded.alpha = 0
        padded.addSubview(nudge)
        view.addSubview(padded)

        NSLayoutConstraint.activate([
            nudge.topAnchor.constraint(equalTo: padded.topAnchor, constant: 8),
            nudge.bottomAnchor.constraint(equalTo: padded.bottomAnchor, constant: -8),
            nudge.leadingAnchor.constraint(equalTo: padded.leadingAnchor, constant: 10),
            nudge.trailingAnchor.constraint(equalTo: padded.trailingAnchor, constant: -10),
            padded.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            padded.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            padded.widthAnchor.constraint(lessThanOrEqualToConstant: 220)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(nudgeTapped(_:)))
        padded.isUserInteractionEnabled = true
        padded.addGestureRecognizer(tap)

        UIView.animate(withDuration: 0.3) { padded.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            UIView.animate(withDuration: 0.5, animations: { padded.alpha = 0 }) { _ in
                padded.removeFromSuperview()
            }
        }
    }

    @objc private func nudgeTapped(_ gesture: UITapGestureRecognizer) {
        gesture.view?.removeFromSuperview()
        presentMapSheet()
    }
}

// MARK: - RegionsServiceDelegate

extension MapViewController: RegionsServiceDelegate {
    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        // The stop the sheet is showing belongs to the region we just left, and
        // `configureMapLayers()` is about to throw away the route-focus layer
        // driving it. Leaving the sheet up would strand it: its arrivals sink
        // would feed a layer no longer on the map, so the lines and vehicles
        // would never come back, and `stopSheetSelection` would stay set — every
        // other marker held down as a gray dot for the rest of the session.
        // Re-attaching the presentation to the rebuilt layer isn't the fix
        // either: shape IDs are region-scoped, so the new region's server would
        // answer this stop's IDs with the wrong lines.
        dismissStopSheetForReplacement()

        // Rebuild region-scoped layers: a new region may gain or lose bikeshare.
        configureMapLayers()
    }

    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        // A regions-list refresh can flip the current region's bikeshare fields in
        // place without changing the region identity; re-evaluate the layers.
        configureMapLayers()
    }
}

// MARK: - RentalLayerActionsDelegate

extension MapViewController: RentalLayerActionsDelegate {
    /// "Plan a trip using this bike": route through the vehicle's exact coordinate
    /// as a via point with a rental mode preselected — OTP has no "use vehicle X"
    /// parameter, but routing through the spot where the vehicle stands picks it up.
    /// Transit + Bikeshare (not Bikeshare Only) because via routing requires a
    /// transit mode in the request on OTP's default configuration.
    func rentalLayer(planTripUsing rental: VehicleRental) {
        application.analytics?.reportEvent(
            pageURL: "app://localhost/bikeshare",
            label: AnalyticsLabels.rentalPlanTripTapped,
            value: rental.rentalNetwork?.networkId
        )
        dismiss(animated: true) { [weak self] in
            self?.showTripPlanner(viaPoint: rental.coordinate, preselectedMode: .transitBikeRental)
        }
    }

    /// Opens a rental deep link. No `canOpenURL` pre-check: Apple's own guidance
    /// is to attempt the open and handle failure, and `open` — unlike
    /// `canOpenURL` — is not constrained by `LSApplicationQueriesSchemes`.
    ///
    /// The URL is often synthesized from a reverse-engineered scheme rather than
    /// published by the feed (see `RentalDeepLink`), so failure is expected and
    /// routine: no app claims the scheme, `success` is false, and we fall back to
    /// the operator's App Store page or web page.
    func rentalLayer(open url: URL, webFallback: URL?, networkID: String?) {
        application.analytics?.reportEvent(
            pageURL: "app://localhost/bikeshare",
            label: AnalyticsLabels.rentalDeepLinkTapped,
            value: networkID
        )

        application.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            Logger.info("Rental deep link failed to open: \(url)")
            self?.application.analytics?.reportEvent(
                pageURL: "app://localhost/bikeshare",
                label: AnalyticsLabels.rentalDeepLinkFallbackFired,
                value: networkID
            )
            if let webFallback {
                self?.application.open(webFallback, options: [:], completionHandler: nil)
            }
        }
    }
}
