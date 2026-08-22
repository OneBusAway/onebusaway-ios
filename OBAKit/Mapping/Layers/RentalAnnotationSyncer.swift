//
//  RentalAnnotationSyncer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import OTPKit

/// Mirrors `RentalLayerCoordinator.visibleRentals` onto an `MKMapView`.
///
/// The coordinator is map-agnostic so the SwiftUI panel can render the same
/// data; this type is the UIKit half that used to live inside it. Exactly one
/// syncer exists per coordinator — **not** one per layer. Bikes and Scooters
/// share a coordinator, so a per-layer syncer would add every annotation twice.
@MainActor final class RentalAnnotationSyncer {

    private weak var mapView: MKMapView?

    /// The annotations currently on the map, by entity id.
    private var annotations: [VehicleRental.ID: RentalAnnotation] = [:]

    private var showsFuelLabels = false
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: RentalLayerCoordinator, mapView: MKMapView) {
        self.mapView = mapView

        coordinator.$visibleRentals
            .sink { [weak self] rentals in self?.sync(to: rentals) }
            .store(in: &cancellables)

        coordinator.$showsFuelLabels
            .sink { [weak self] shows in self?.applyFuelLabelVisibility(shows) }
            .store(in: &cancellables)
    }

    /// Brings the map in line with `rentals`, reusing annotation objects for
    /// entities that are still present.
    func sync(to rentals: [VehicleRental]) {
        guard let mapView else { return }

        let incoming = Dictionary(rentals.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

        var removed: [RentalAnnotation] = []
        for (id, annotation) in annotations where incoming[id] == nil {
            annotations.removeValue(forKey: id)
            removed.append(annotation)
        }
        mapView.removeAnnotations(removed)

        var added: [RentalAnnotation] = []
        for rental in rentals {
            if let existing = annotations[rental.id] {
                existing.update(with: rental)
                // Re-assigning re-runs the view's configure() so glyphs, tint,
                // and the fuel label track the data; identity is unchanged, so
                // selection and any open callout survive.
                if let view = mapView.view(for: existing) as? RentalAnnotationView {
                    view.annotation = existing
                }
            } else {
                let annotation = RentalAnnotation(rental: rental)
                annotation.showsFuelLabel = showsFuelLabels
                annotations[rental.id] = annotation
                added.append(annotation)
            }
        }
        mapView.addAnnotations(added)
    }

    /// Pushes the current zoom's label decision onto every annotation without
    /// re-running a full reconfigure per marker.
    private func applyFuelLabelVisibility(_ shows: Bool) {
        showsFuelLabels = shows
        guard let mapView else { return }
        for annotation in annotations.values {
            annotation.showsFuelLabel = shows
            (mapView.view(for: annotation) as? RentalAnnotationView)?.setShowsFuelLabel(shows)
        }
    }

    /// Re-adds every tracked annotation after a wholesale `removeAllAnnotations`
    /// (search flows). `addAnnotations` ignores members already present, so this
    /// is safe to call unconditionally.
    func reattachAnnotations() {
        guard let mapView, !annotations.isEmpty else { return }
        mapView.addAnnotations(Array(annotations.values))
    }
}
