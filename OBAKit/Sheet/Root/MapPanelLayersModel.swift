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

    private var lastSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    private var lastMapSize: CGSize = .zero
    private var rentalCancellables = Set<AnyCancellable>()

    private let application: Application
    private var registrar: MapLayerRegistrar!
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
    }

    /// (Re-)binds to the registrar's current coordinator. `MapLayerRegistrar`
    /// builds a fresh one on every region change, so an old subscription would
    /// keep delivering the previous region's vehicles.
    private func subscribeToRentalCoordinator() {
        rentalCancellables.removeAll()

        guard let coordinator = registrar.rentalCoordinator else {
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
    func updateViewport(span: MKCoordinateSpan, mapSize: CGSize) {
        lastSpan = span
        lastMapSize = mapSize
        recomputeClusters()
    }

    private func recomputeClusters() {
        rentalItems = RentalClustering.items(
            for: visibleRentals,
            span: lastSpan,
            mapSize: lastMapSize
        )
    }

    // MARK: - Route resolution

    /// When the rental data arrived — feeds the detail sheet's freshness line.
    var rentalFetchedAt: Date? { registrar.rentalCoordinator?.lastSnapshotAt }

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
