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

        configureRentalLayers()
        updateMapLayerBadge()
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
