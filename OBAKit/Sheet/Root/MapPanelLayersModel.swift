//
//  MapPanelLayersModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import MapKit
import OBAKitCore
import OTPKit

/// The SwiftUI panel's window onto the map layer system.
///
/// `MapSheetView` writes through `MapRegionManager`, which owns the persistence
/// and posts notifications. This model turns those notifications into published
/// state so the panel's `Map` re-renders — the UIKit surface gets the same
/// effect from `MKMapView` delegate callbacks it has no counterpart to here.
///
/// Retains the registrar because `RegionsService` holds delegates weakly.
@MainActor final class MapPanelLayersModel: ObservableObject {

    @Published private(set) var isStopsLayerEnabled = true
    @Published private(set) var showsPointsOfInterest = true

    /// Drives the badge on the map-type button — the panel's only at-a-glance
    /// readout of layer state.
    @Published private(set) var enabledLayerCount = 0

    /// Clustered rental markers for the current viewport.
    @Published private(set) var rentalItems: [RentalMapItem] = []

    /// Whether the current zoom is tight enough to show fuel figures.
    @Published private(set) var showsFuelLabels = false

    /// Every rental currently visible, before clustering. Backs id resolution
    /// for the rental sheet routes.
    private var visibleRentals: [VehicleRental] = []

    /// Zero until the first camera settle. `RentalClustering` treats a
    /// degenerate rect as "no viewport yet" and emits one item per rental, which
    /// is the honest fallback before the map has reported where it is looking.
    private var lastMapRect = MKMapRect(x: 0, y: 0, width: 0, height: 0)
    private var lastMapSize: CGSize = .zero
    private var rentalCancellables = Set<AnyCancellable>()

    /// The coordinator `rentalCancellables` is currently subscribed to.
    ///
    /// Held strongly on purpose: comparing identity against a `weak` reference
    /// would be unsound, because a zeroed reference cannot be told apart from a
    /// fresh coordinator that happened to be allocated at the same address. The
    /// retention lasts only until the next `refresh()` swaps it out.
    private var boundRentalCoordinator: RentalLayerCoordinator?

    private let application: Application

    /// Exposed (not `private`) so `MapPanelLayersModelTests` can push snapshots
    /// through the live coordinator, the same reason `RentalLayerCoordinator`
    /// exposes `apply(_:)`. Nothing on the panel reads it.
    private(set) var registrar: MapLayerRegistrar!
    private var cancellables = Set<AnyCancellable>()

    init(application: Application) {
        self.application = application

        registrar = MapLayerRegistrar(application: application) { [weak self] _ in
            self?.refresh()
        }
        registrar.configure()

        let center = NotificationCenter.default
        for name in [
            Notification.Name.mapLayerEnabledStateDidChange,
            .mapLayerAvailabilityDidChange,
            .mapPointsOfInterestVisibilityDidChange,
            .rentalRangeFilterDidChange
        ] {
            center.publisher(for: name)
                .sink { [weak self] _ in
                    // Every one of these notifications is posted from @MainActor code
                    // (MapRegionManager's setters, RentalLayerCoordinator's availability
                    // updates). Asserting that here keeps delivery synchronous — so the
                    // panel's published state is correct in the same turn the sheet
                    // writes it — while trapping loudly if a future writer ever posts
                    // from a background thread.
                    MainActor.assumeIsolated { self?.refresh() }
                }
                .store(in: &cancellables)
        }

        refresh()
    }

    private var mapRegionManager: MapRegionManager { application.mapRegionManager }

    private func refresh() {
        isStopsLayerEnabled = mapRegionManager.isStopsLayerEnabled
        showsPointsOfInterest = mapRegionManager.mapViewShowsPointsOfInterest
        enabledLayerCount = mapRegionManager.enabledMapLayerCount
        subscribeToRentalCoordinator()

        // The Map sheet writes the threshold through `MapRegionManager` and
        // posts `.rentalRangeFilterDidChange`; on this surface nothing else
        // carries it to the coordinator, so without this the filter (and the
        // range half of Reset) would persist but never change what is drawn
        // until the next region change or launch. `MapViewController` does the
        // same for the UIKit map. `RentalVisibility.setFilter` no-ops when the
        // value is unchanged, so running it on every refresh is free.
        registrar.rentalCoordinator?.setRangeFilter(mapRegionManager.rentalRangeFilter)
    }

    /// (Re-)binds to the registrar's current coordinator. `MapLayerRegistrar`
    /// builds a fresh one on every region change, so an old subscription would
    /// keep delivering the previous region's vehicles.
    ///
    /// Rebinding only when the identity changes matters: `@Published` replays
    /// its current value to every new subscriber, so re-subscribing on each
    /// `refresh()` would re-deliver the whole rental list and recluster it every
    /// time an unrelated toggle (points of interest, a layer switch) posted.
    private func subscribeToRentalCoordinator() {
        let coordinator = registrar.rentalCoordinator
        guard coordinator !== boundRentalCoordinator else { return }
        boundRentalCoordinator = coordinator

        rentalCancellables.removeAll()

        guard let coordinator else {
            visibleRentals = []
            rentalItems = []
            showsFuelLabels = false
            return
        }

        coordinator.$visibleRentals
            .sink { [weak self] rentals in
                self?.visibleRentals = rentals
                self?.recomputeClusters()
            }
            .store(in: &rentalCancellables)

        coordinator.$showsFuelLabels
            .sink { [weak self] shows in self?.showsFuelLabels = shows }
            .store(in: &rentalCancellables)
    }

    /// Records the viewport geometry clustering needs and recomputes.
    func updateViewport(mapRect: MKMapRect, mapSize: CGSize) {
        lastMapRect = mapRect
        lastMapSize = mapSize
        recomputeClusters()
    }

    /// Records the map's reported size on its own and recomputes.
    ///
    /// The panel learns its size from `.onGeometryChange`, which can report the
    /// first non-zero size *after* the camera has already settled. In that
    /// ordering `updateViewport(mapRect:mapSize:)` ran with `.zero`, clustering
    /// took its no-layout fallback of one marker per vehicle, and nothing would
    /// recompute until the rider next moved the map — leaving the first screen
    /// of a dense area completely unclustered.
    func updateMapSize(_ mapSize: CGSize) {
        guard mapSize != lastMapSize else { return }
        lastMapSize = mapSize
        recomputeClusters()
    }

    private func recomputeClusters() {
        rentalItems = RentalClustering.items(
            for: visibleRentals,
            mapRect: lastMapRect,
            mapSize: lastMapSize
        )
    }

    // MARK: - Route resolution

    /// When the rental data arrived — feeds the detail sheet's freshness line.
    var rentalFetchedAt: Date? { registrar.rentalCoordinator?.lastSnapshotAt }

    /// The rental layer's own trust window, read from the layer rather than
    /// restated, so the panel's freshness footer cannot drift from the UIKit
    /// map's. Both rental layers declare the same window, so either answers.
    var rentalStaleAfter: Duration? { registrar.rentalLayers.first?.staleAfter }

    /// The rider's location, for walk-time estimates in detail sheets.
    var rentalUserLocation: CLLocation? { registrar.rentalCoordinator?.userLocation }

    /// Resolves a route's id back to a live model. Returns nil once the vehicle
    /// has left the feed, so an open sheet reflects reality rather than a
    /// snapshot taken at push time.
    func rental(withID id: VehicleRental.ID) -> VehicleRental? {
        visibleRentals.first { $0.id == id }
    }

    func rentals(withIDs ids: [VehicleRental.ID]) -> [VehicleRental] {
        let wanted = Set(ids)
        return visibleRentals.filter { wanted.contains($0.id) }
    }

    /// Feeds the panel's camera into the layer pipeline. The `MKMapView` this
    /// manager owns is never laid out in panel mode, so nothing else would.
    func viewportDidChange(_ rect: MKMapRect) {
        mapRegionManager.mapLayersViewportDidChange(rect)
    }
}
