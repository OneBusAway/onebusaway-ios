//
//  RentalLayerCoordinator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import OTPKit

/// The shared engine behind the Bikes and Scooters map layers.
///
/// Both layers are backed by one `VehicleRentalSource`: enabling both fetches once
/// with the union of their form factors, and the snapshot is partitioned at
/// annotation-creation time. All debounce, cancellation, and diffing live in the
/// framework — this class only converts viewports, applies diffed snapshots to the
/// map, and tracks runtime availability from fetch outcomes.
@MainActor final class RentalLayerCoordinator {

    private let source: VehicleRentalSource
    private weak var mapView: MKMapView?

    /// Form factors per enabled layer id. The source fetches the union.
    private var enabledLayerFactors: [String: Set<VehicleFormFactor>] = [:]

    private var annotations: [VehicleRental.ID: RentalAnnotation] = [:]

    /// When the last successful snapshot arrived; drives freshness lines.
    private(set) var lastSnapshotAt: Date?

    /// The rider's location, for walk-time estimates in detail sheets.
    var userLocation: CLLocation? {
        mapView?.userLocation.location
    }

    /// Configuration promises the layer works; only a fetch can prove it. Optimistic
    /// until the first failure, healed by any later success.
    private(set) var availability: MapLayerAvailability = .available

    private var snapshotTask: Task<Void, Never>?
    private var failureTask: Task<Void, Never>?
    private var lastMapRect: MKMapRect?

    init(service: VehicleRentalService, mapView: MKMapView) {
        self.source = VehicleRentalSource(service: service)
        self.mapView = mapView

        let snapshots = source.snapshots
        snapshotTask = Task { [weak self] in
            for await snapshot in snapshots {
                self?.apply(snapshot)
            }
        }

        let failures = source.fetchFailures
        failureTask = Task { [weak self] in
            for await failure in failures {
                self?.handle(failure)
            }
        }
    }

    deinit {
        snapshotTask?.cancel()
        failureTask?.cancel()
    }

    // MARK: - Layer Inputs

    var hasEnabledLayers: Bool { !enabledLayerFactors.isEmpty }

    private var combinedFormFactors: Set<VehicleFormFactor> {
        enabledLayerFactors.values.reduce(into: Set<VehicleFormFactor>()) { $0.formUnion($1) }
    }

    func setLayer(id: String, enabled: Bool, formFactors: Set<VehicleFormFactor>) {
        if enabled {
            enabledLayerFactors[id] = formFactors
        } else {
            enabledLayerFactors.removeValue(forKey: id)
        }

        let factors = combinedFormFactors
        pruneAnnotations(notMatching: factors)

        let mapRect = lastMapRect
        Task {
            if factors.isEmpty {
                await source.reset()
            } else {
                await source.setFormFactors(factors)
                // Re-prime the viewport: after a reset (all layers off) the source
                // has no viewport to refetch with. Redundant calls coalesce into
                // one fetch, so this is safe to do unconditionally.
                if let mapRect {
                    await source.setViewport(Self.boundingBox(for: mapRect))
                }
            }
        }
    }

    /// `mapRect` is nil when the zoom gate is closed — everything is removed.
    func viewportDidChange(_ mapRect: MKMapRect?) {
        lastMapRect = mapRect
        guard hasEnabledLayers else { return }

        // The layer might have been dimmed by an earlier failure; a region change
        // is the retry trigger, so let the next fetch decide again.
        let boundingBox = mapRect.map(Self.boundingBox(for:))
        Task {
            await source.setViewport(boundingBox)
        }
    }

    // MARK: - Snapshot Application

    private func apply(_ snapshot: VehicleRentalSnapshot) {
        lastSnapshotAt = snapshot.fetchedAt
        setAvailability(.available)

        if !snapshot.partialErrors.isEmpty {
            Logger.info("Rental fetch partial errors: \(snapshot.partialErrors.joined(separator: "; "))")
        }

        guard let mapView else { return }

        for id in snapshot.removed {
            if let annotation = annotations.removeValue(forKey: id) {
                mapView.removeAnnotation(annotation)
            }
        }

        for rental in snapshot.updated {
            guard let annotation = annotations[rental.id] else { continue }
            annotation.update(with: rental)
            // Re-assigning the annotation re-runs the view's configure() so glyphs
            // (availability counts) and tint (operative state) track the data;
            // identity is unchanged, so selection survives.
            if let view = mapView.view(for: annotation) as? RentalAnnotationView {
                view.annotation = annotation
            }
        }

        let factors = combinedFormFactors
        guard !factors.isEmpty else { return }

        var added: [RentalAnnotation] = []
        for rental in snapshot.added where annotations[rental.id] == nil && rental.matches(formFactors: factors) {
            let annotation = RentalAnnotation(rental: rental)
            annotations[rental.id] = annotation
            added.append(annotation)
        }
        mapView.addAnnotations(added)
    }

    private func handle(_ failure: VehicleRentalSource.FetchFailure) {
        Logger.error("Rental fetch failed: \(failure.message)")

        // A browse layer never alerts; a failure with nothing on the map dims the
        // layer row instead, so an empty layer is never silently "on".
        if annotations.isEmpty {
            setAvailability(.unavailable(reason: OBALoc(
                "map_layers.rental_unavailable",
                value: "Not available right now",
                comment: "Reason shown on a dimmed rental layer row when its server is unreachable"
            )))
        }
    }

    /// Re-adds every tracked annotation to the map after a wholesale
    /// `removeAllAnnotations` (search flows). `addAnnotations` ignores members
    /// that are already present, so this is safe to call unconditionally.
    func reattachAnnotations() {
        guard let mapView, !annotations.isEmpty else { return }
        mapView.addAnnotations(Array(annotations.values))
    }

    private func pruneAnnotations(notMatching factors: Set<VehicleFormFactor>) {
        guard let mapView else { return }

        var removed: [RentalAnnotation] = []
        for (id, annotation) in annotations {
            let stillVisible = !factors.isEmpty && annotation.rental.matches(formFactors: factors)
            if !stillVisible {
                annotations.removeValue(forKey: id)
                removed.append(annotation)
            }
        }
        mapView.removeAnnotations(removed)
    }

    private func setAvailability(_ newValue: MapLayerAvailability) {
        guard availability != newValue else { return }
        availability = newValue
        for id in enabledLayerFactors.keys {
            NotificationCenter.default.post(name: .mapLayerAvailabilityDidChange, object: id)
        }
    }

    // MARK: - Geometry

    private static func boundingBox(for mapRect: MKMapRect) -> VehicleRentalBoundingBox {
        let region = MKCoordinateRegion(mapRect)
        return VehicleRentalBoundingBox(
            minimumLatitude: region.center.latitude - region.span.latitudeDelta / 2.0,
            maximumLatitude: region.center.latitude + region.span.latitudeDelta / 2.0,
            minimumLongitude: region.center.longitude - region.span.longitudeDelta / 2.0,
            maximumLongitude: region.center.longitude + region.span.longitudeDelta / 2.0
        )
    }
}
