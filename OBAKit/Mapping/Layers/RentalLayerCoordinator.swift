//
//  RentalLayerCoordinator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
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
/// range threshold — before publishing the resulting diffs, and it tracks runtime
/// availability from fetch outcomes. Both the UIKit map (through `RentalAnnotationSyncer`)
/// and the SwiftUI panel render from the published state.
@MainActor final class RentalLayerCoordinator: ObservableObject {

    private let source: VehicleRentalSource
    private let locationService: LocationService

    /// Form factors per enabled layer id. The source fetches the union.
    private var enabledLayerFactors: [String: Set<VehicleFormFactor>] = [:]

    /// Decides which delivered rentals belong on the map. All the caching and
    /// diffing lives here; this class only applies the result to published state.
    private var visibility = RentalVisibility()

    /// The rentals that currently belong on the map, sorted by id.
    ///
    /// Both surfaces render from this: the UIKit map through
    /// `RentalAnnotationSyncer`, the SwiftUI panel by clustering it. Sorting is
    /// not cosmetic — an unstable order reshuffles the panel's `ForEach` on
    /// every snapshot.
    @Published private(set) var visibleRentals: [VehicleRental] = []

    /// Whether the current zoom is tight enough to show fuel figures.
    @Published private(set) var showsFuelLabels = false

    /// Keyed store behind `visibleRentals`. Must stay equal to
    /// `RentalVisibility`'s visible-id set — see `applyChanges(_:)`.
    private var rentalsByID: [VehicleRental.ID: VehicleRental] = [:]

    /// Fuel labels need more room than the markers do, so they gate on a tighter
    /// window than the layer's own `zoomWindow` (20,000-point) — the labels are
    /// subviews and don't participate in MapKit's collision logic. Same type, so
    /// the two spellings of "is this viewport small enough" stay in sync. At
    /// latitude 47.6 there are 9.9464 map points per metre, making 8,000 map
    /// points (`MKMapRect` units, not metres) an 804 m-tall viewport — a few blocks.
    private static let fuelLabelZoomWindow = MapLayerZoomWindow(maxVisibleHeight: 8_000)

    /// When the last successful snapshot arrived; drives freshness lines.
    private(set) var lastSnapshotAt: Date?

    /// The rider's location, for walk-time estimates in detail sheets.
    var userLocation: CLLocation? {
        locationService.currentLocation
    }

    /// Configuration promises the layer works; only a fetch can prove it. Optimistic
    /// until the first failure, healed by any later success.
    private(set) var availability: MapLayerAvailability = .available

    private var snapshotTask: Task<Void, Never>?
    private var failureTask: Task<Void, Never>?
    private var lastMapRect: MKMapRect?

    init(service: VehicleRentalService, locationService: LocationService) {
        self.source = VehicleRentalSource(service: service)
        self.locationService = locationService

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
        applyChanges(visibility.setFormFactors(factors))

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
        applyChanges(visibility.setFilter(filter))
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

    /// Publishes the current zoom's label decision. Cheap: `@Published` still
    /// fires on every write, so the equality guard stays.
    private func updateFuelLabelVisibility(for mapRect: MKMapRect?) {
        let shows = mapRect.map { Self.fuelLabelZoomWindow.contains(visibleHeight: $0.height) } ?? false
        guard shows != showsFuelLabels else { return }
        showsFuelLabels = shows
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

        applyChanges(visibility.apply(snapshot))
    }

    /// Folds a visibility diff into `rentalsByID` and republishes.
    ///
    /// The only place this class mutates `rentalsByID` — it must keep
    /// `Set(rentalsByID.keys)` equal to `RentalVisibility`'s visible-id set. Do
    /// not add an early return that skips a branch: one would silently break
    /// that invariant and, with it, cache restore when a filter is relaxed.
    private func applyChanges(_ changes: RentalVisibility.Changes) {
        guard !changes.isEmpty else { return }

        for id in changes.removed {
            rentalsByID.removeValue(forKey: id)
        }
        for rental in changes.updated where rentalsByID[rental.id] != nil {
            rentalsByID[rental.id] = rental
        }
        for rental in changes.added {
            rentalsByID[rental.id] = rental
        }

        visibleRentals = rentalsByID.values.sorted { $0.id < $1.id }
    }

    private func handle(_ failure: VehicleRentalSource.FetchFailure) {
        Logger.error("Rental fetch failed: \(failure.message)")

        // A browse layer never alerts; a failure with nothing on the map dims the
        // layer row instead, so an empty layer is never silently "on".
        if visibleRentals.isEmpty {
            setAvailability(.unavailable(reason: OBALoc(
                "map_layers.rental_unavailable",
                value: "Not available right now",
                comment: "Reason shown on a dimmed rental layer row when its server is unreachable"
            )))
        }
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
