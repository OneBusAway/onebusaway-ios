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
/// annotation-creation time. Fetch debounce and cancellation live in OTPKit's
/// `VehicleRentalSource`; this class runs delivered snapshots through a second,
/// client-side visibility pass — `RentalVisibility`, gating on form factors and the
/// range threshold — before converting viewports and applying the resulting diffs
/// to the map, and it tracks runtime availability from fetch outcomes.
@MainActor final class RentalLayerCoordinator {

    private let source: VehicleRentalSource
    private weak var mapView: MKMapView?

    /// Form factors per enabled layer id. The source fetches the union.
    private var enabledLayerFactors: [String: Set<VehicleFormFactor>] = [:]

    /// Decides which delivered rentals belong on the map. All the caching and
    /// diffing lives here; this class only applies the result to the map view.
    private var visibility = RentalVisibility()

    /// The annotations currently on the map, by entity id.
    private var annotations: [VehicleRental.ID: RentalAnnotation] = [:]

    /// Fuel labels need more room than the markers do, so they gate on a tighter
    /// window than the layer's own `zoomWindow` (20,000-point) — the labels are
    /// subviews and don't participate in MapKit's collision logic. Same type, so
    /// the two spellings of "is this viewport small enough" stay in sync. At
    /// latitude 47.6 there are 9.9464 map points per metre, making 8,000 map
    /// points (`MKMapRect` units, not metres) an 804 m-tall viewport — a few blocks.
    private static let fuelLabelZoomWindow = MapLayerZoomWindow(maxVisibleHeight: 8_000)

    private var showsFuelLabels = false

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
        syncMapView(with: visibility.setFormFactors(factors))

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

    /// Applies a new minimum-range threshold. Purely client-side: the entities are
    /// already cached, so relaxing the threshold restores vehicles with no refetch.
    func setRangeFilter(_ filter: RentalRangeFilter) {
        syncMapView(with: visibility.setFilter(filter))
    }

    /// `mapRect` is nil when the zoom gate is closed — everything is removed.
    func viewportDidChange(_ mapRect: MKMapRect?) {
        lastMapRect = mapRect
        updateFuelLabelVisibility(for: mapRect)
        guard hasEnabledLayers else { return }

        // The layer might have been dimmed by an earlier failure; a region change
        // is the retry trigger, so let the next fetch decide again.
        let boundingBox = mapRect.map(Self.boundingBox(for:))
        Task {
            await source.setViewport(boundingBox)
        }
    }

    /// Pushes the current zoom's label decision onto every annotation. Cheap: it
    /// no-ops unless the gate actually flipped.
    private func updateFuelLabelVisibility(for mapRect: MKMapRect?) {
        let shows = mapRect.map { Self.fuelLabelZoomWindow.contains(visibleHeight: $0.height) } ?? false
        guard shows != showsFuelLabels else { return }
        showsFuelLabels = shows

        guard let mapView else { return }
        for annotation in annotations.values {
            annotation.showsFuelLabel = shows
            (mapView.view(for: annotation) as? RentalAnnotationView)?.setShowsFuelLabel(shows)
        }
    }

    // MARK: - Snapshot Application

    // Exposed (not `private`) so RentalLayerCoordinatorTests can feed snapshots
    // directly and drive the synchronous filter path without going through the
    // async `AsyncStream`/debounce plumbing.
    func apply(_ snapshot: VehicleRentalSnapshot) {
        lastSnapshotAt = snapshot.fetchedAt
        setAvailability(.available)

        if !snapshot.partialErrors.isEmpty {
            Logger.info("Rental fetch partial errors: \(snapshot.partialErrors.joined(separator: "; "))")
        }

        syncMapView(with: visibility.apply(snapshot))
    }

    /// Translates a visibility diff into map view operations. The only place this
    /// class mutates the `annotations` dictionary — it must keep `Set(annotations.keys)`
    /// equal to `RentalVisibility`'s visible-id set. Do not add an early return here:
    /// one that skips a branch (e.g. on an empty `added`/`removed`/`updated` array)
    /// would silently break that invariant and, with it, cache restore.
    private func syncMapView(with changes: RentalVisibility.Changes) {
        guard let mapView, !changes.isEmpty else { return }

        var removed: [RentalAnnotation] = []
        for id in changes.removed {
            if let annotation = annotations.removeValue(forKey: id) {
                removed.append(annotation)
            }
        }
        mapView.removeAnnotations(removed)

        for rental in changes.updated {
            guard let annotation = annotations[rental.id] else { continue }
            annotation.update(with: rental)
            // Re-assigning the annotation re-runs the view's configure() so glyphs
            // (availability counts), tint (operative state), and the fuel label
            // track the data; identity is unchanged, so selection survives.
            if let view = mapView.view(for: annotation) as? RentalAnnotationView {
                view.annotation = annotation
            }
        }

        var added: [RentalAnnotation] = []
        for rental in changes.added where annotations[rental.id] == nil {
            let annotation = RentalAnnotation(rental: rental)
            annotation.showsFuelLabel = showsFuelLabels
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
