//
//  RentalMapLayer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OTPKit

/// A rental micromobility layer — Bikes or Scooters — on the main map.
///
/// The two sibling layers share one `RentalLayerCoordinator` (and thus one
/// `VehicleRentalSource`), so enabling both costs one fetch. Each layer only
/// declares what it shows; the coordinator does the work.
@MainActor final class RentalMapLayer: NSObject, MapLayer {

    static let bikesLayerID = "bikes"
    static let scootersLayerID = "scooters"

    let id: String
    let title: String
    let iconName: String
    let isEnabledByDefault: Bool
    let formFactors: Set<VehicleFormFactor>

    private let coordinator: RentalLayerCoordinator

    /// Receives detail-sheet actions ("Plan a trip using this bike", deep links).
    /// Set by `MapViewController` at registration.
    weak var actionsDelegate: RentalLayerActionsDelegate?

    /// Builds the Bikes layer: enabled by default so the first-run map is useful,
    /// fail-open entities included (matching the framework filter).
    static func bikesLayer(coordinator: RentalLayerCoordinator) -> RentalMapLayer {
        RentalMapLayer(
            id: bikesLayerID,
            title: OBALoc("map_layers.bikes", value: "Bikes", comment: "Map sheet row for the rental bikes layer"),
            iconName: "bicycle",
            isEnabledByDefault: true,
            formFactors: [.bicycle, .cargoBicycle],
            coordinator: coordinator
        )
    }

    /// Builds the Scooters layer: off by default to keep the first-run map calm,
    /// but one tap away — scooters are 74% of the launch region's supply.
    static func scootersLayer(coordinator: RentalLayerCoordinator) -> RentalMapLayer {
        RentalMapLayer(
            id: scootersLayerID,
            title: OBALoc("map_layers.scooters", value: "Scooters", comment: "Map sheet row for the rental scooters layer"),
            iconName: "scooter",
            isEnabledByDefault: false,
            formFactors: [.scooter, .scooterSeated, .scooterStanding],
            coordinator: coordinator
        )
    }

    private init(
        id: String,
        title: String,
        iconName: String,
        isEnabledByDefault: Bool,
        formFactors: Set<VehicleFormFactor>,
        coordinator: RentalLayerCoordinator
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.isEnabledByDefault = isEnabledByDefault
        self.formFactors = formFactors
        self.coordinator = coordinator
        super.init()
    }

    // MARK: - MapLayer

    var tintColor: UIColor { .rentalPurple }
    var group: MapLayerGroup { .otherModes }
    var availability: MapLayerAvailability { coordinator.availability }

    /// Stricter than the stop gate (40,000): `vehicleRentalsByBbox` has no
    /// server-side result limit, so the client must keep bounding boxes small.
    var zoomWindow: MapLayerZoomWindow { MapLayerZoomWindow(maxVisibleHeight: 20_000) }

    var densityBudget: Int { 500 }
    var isClusterable: Bool { true }
    var refreshPolicy: MapLayerRefreshPolicy { .onViewportChange }

    /// Riders distrust stale micromobility data faster than stale bus data.
    var staleAfter: Duration? { .seconds(120) }

    /// When the last rental data arrived — feeds the detail sheet's freshness line.
    var lastSnapshotAt: Date? { coordinator.lastSnapshotAt }

    func activate() {
        coordinator.setLayer(id: id, enabled: true, formFactors: formFactors)
    }

    func deactivate() {
        coordinator.setLayer(id: id, enabled: false, formFactors: formFactors)
    }

    func viewportDidChange(_ mapRect: MKMapRect?) {
        coordinator.viewportDidChange(mapRect)
    }

    func mapAnnotationsWereCleared() {
        coordinator.reattachAnnotations()
    }

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
        if annotation is RentalAnnotation {
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapView.reuseIdentifier(for: RentalAnnotationView.self),
                for: annotation
            )
        }

        // Claim only rental clusters. Registering the default cluster reuse
        // identifier instead would take over cluster rendering for every
        // annotation type on the map.
        if let cluster = annotation as? MKClusterAnnotation, cluster.memberAnnotations.first is RentalAnnotation {
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapView.reuseIdentifier(for: RentalClusterAnnotationView.self),
                for: annotation
            )
        }

        return nil
    }

    /// Rentals are ambient context: while a stop sheet is up they recede to gray
    /// dots so the selected stop's route lines stay legible.
    ///
    /// Recognizes exactly what `annotationView(for:in:)` above claims — the two
    /// must agree, or a rental either keeps its full marker behind the sheet or
    /// disappears from the map instead of receding.
    func recedesBehindStopSheet(_ annotation: MKAnnotation) -> Bool {
        if annotation is RentalAnnotation { return true }
        if let cluster = annotation as? MKClusterAnnotation {
            return cluster.memberAnnotations.first is RentalAnnotation
        }
        return false
    }

    func detailViewController(for annotation: MKAnnotation) -> UIViewController? {
        if let rentalAnnotation = annotation as? RentalAnnotation {
            return RentalDetailViewController(
                rental: rentalAnnotation.rental,
                fetchedAt: coordinator.lastSnapshotAt,
                staleAfter: staleAfter,
                userLocation: coordinator.userLocation,
                actionsDelegate: actionsDelegate
            )
        }

        if let cluster = annotation as? MKClusterAnnotation {
            let rentals = cluster.memberAnnotations.compactMap { ($0 as? RentalAnnotation)?.rental }
            guard !rentals.isEmpty else { return nil }
            return RentalClusterListViewController(
                rentals: rentals,
                fetchedAt: coordinator.lastSnapshotAt,
                staleAfter: staleAfter,
                userLocation: coordinator.userLocation,
                actionsDelegate: actionsDelegate
            )
        }

        return nil
    }
}
