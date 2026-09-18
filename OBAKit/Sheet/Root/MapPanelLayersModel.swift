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

    /// The panel's route to whatever lives on the live layers rather than in
    /// published state: the range filter in `refresh()`, and `rentalFetchedAt` /
    /// `rentalStaleAfter` / `rentalUserLocation` behind the rental sheets. Also
    /// how the tests push snapshots through the coordinator.
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

        // A rebind means a new region's coordinator, so anything held for the old
        // region's sheets is now wrong rather than merely stale.
        pinnedRentals.removeAll()
        pinOrder.removeAll()

        guard let coordinator else {
            visibleRentals = []
            lastReportedRentals = []
            rentalItems = []
            showsFuelLabels = false
            return
        }

        coordinator.$visibleRentals
            .sink { [weak self] rentals in
                guard let self else { return }
                self.visibleRentals = rentals
                if !rentals.isEmpty {
                    self.lastReportedRentals = rentals
                }
                self.recomputeClusters()
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

    /// Assigns only on a real change.
    ///
    /// This runs on every camera settle, and `@Published` fires on assignment
    /// rather than on difference — so an unconditional write re-rendered the
    /// whole panel body, `factory.view(for:)` included, each time the rider
    /// nudged the map without moving a single marker. Panning within one grid
    /// cell is the common case.
    private func recomputeClusters() {
        let items = RentalClustering.items(
            for: visibleRentals,
            mapRect: lastMapRect,
            mapSize: lastMapSize
        )
        guard items != rentalItems else { return }
        rentalItems = items
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

    /// The last non-empty vehicle list the feed produced, retained for id resolution.
    ///
    /// Never drawn — `rentalItems` is computed from `visibleRentals` alone, so nothing
    /// stale reaches the map. This exists only so an open sheet can still name the vehicle
    /// it was opened for while the feed has nothing to say. See `resolutionSource`.
    private var lastReportedRentals: [VehicleRental] = []

    /// Vehicles an open sheet is about, held until the coordinator is rebuilt.
    ///
    /// `lastReportedRentals` covers the feed going silent *wholesale*. It cannot cover the
    /// other half: the feed still reporting, from a viewport that no longer contains this
    /// vehicle. Framing a planned trip re-fetches for the itinerary's bounding box, and
    /// every bike outside it arrives back as a removal — indistinguishable, in the
    /// snapshot, from one a rider just rode away. So a sheet two layers down watched its
    /// own vehicle vanish and flipped to "Not available right now".
    ///
    /// Pinning happens where the sheet is opened — a map tap or a cluster row — which is
    /// the one moment the vehicle is unambiguously live: the rider just touched it. From
    /// then on the sheet keeps naming what it was opened for, and freshness is reported by
    /// the sheet's own `fetchedAt` / `staleAfter` footer, which exists for exactly this.
    private var pinnedRentals: [VehicleRental.ID: VehicleRental] = [:]

    /// Insertion order for `pinnedRentals`, so the cap below evicts oldest-first.
    private var pinOrder: [VehicleRental.ID] = []

    /// Pins are only released wholesale, on a region change, so this bounds a long
    /// session. A rider opening more than this many rental sheets without changing region
    /// has long since stopped looking at the first one.
    private static let pinnedRentalLimit = 64

    /// Holds onto the vehicles a sheet is being opened for. Call from the push site.
    func pinForOpenSheet(_ rentals: [VehicleRental]) {
        for rental in rentals where pinnedRentals.updateValue(rental, forKey: rental.id) == nil {
            pinOrder.append(rental.id)
        }

        while pinOrder.count > Self.pinnedRentalLimit {
            pinnedRentals.removeValue(forKey: pinOrder.removeFirst())
        }
    }

    /// What `rental(withID:)` and `rentals(withIDs:)` resolve against.
    ///
    /// `visibleRentals` is viewport-scoped and zoom-gated: pan away or zoom out past the
    /// layer's window and `MapRegionManager.forwardViewport(to:)` hands the coordinator a
    /// nil viewport, emptying it. That is the feed falling silent, not every vehicle
    /// disappearing — but a sheet resolving against it reads the two identically and flips
    /// to its "not available" state. Framing a planned trip zooms out far enough to do
    /// this every time, which is how ending a trip left two dead rental sheets underneath
    /// the planner; a rider pinching out with a rental sheet open hit the same thing.
    ///
    /// The fallback is deliberately narrow: only when the feed is *not* reporting and has
    /// therefore emptied the list wholesale. While it is reporting, the live list is the
    /// only truth — a vehicle missing from it really is gone, and saying so is the point of
    /// resolving by id rather than carrying the model in the route. An area that genuinely
    /// holds no vehicles still reads as empty.
    private var resolutionSource: [VehicleRental] {
        let isReporting = registrar.rentalCoordinator?.isReportingVehicles ?? false
        guard !isReporting, visibleRentals.isEmpty else { return visibleRentals }
        return lastReportedRentals
    }

    /// Resolves a route's id back to a model: the live list first, then anything pinned
    /// for an open sheet, then the last report the feed made.
    ///
    /// Resolving live-first is what keeps an open sheet current — a vehicle's range and
    /// position update under it as the feed refreshes. The fallbacks only answer when the
    /// live list cannot, and each covers a different way of "cannot": see `pinnedRentals`
    /// and `resolutionSource`. Nil still means nil for a vehicle the panel has never seen.
    func rental(withID id: VehicleRental.ID) -> VehicleRental? {
        resolutionSource.first { $0.id == id } ?? pinnedRentals[id]
    }

    func rentals(withIDs ids: [VehicleRental.ID]) -> [VehicleRental] {
        let live = resolutionSource.filter { ids.contains($0.id) }
        let liveIDs = Set(live.map(\.id))
        // Order follows `ids` for the members the live list did not answer, so a cluster
        // list does not reshuffle as vehicles drop in and out of the viewport.
        return live + ids.compactMap { liveIDs.contains($0) ? nil : pinnedRentals[$0] }
    }

    /// Feeds the panel's camera into the layer pipeline. The `MKMapView` this
    /// manager owns is never laid out in panel mode, so nothing else would.
    func viewportDidChange(_ rect: MKMapRect) {
        mapRegionManager.mapLayersViewportDidChange(rect)
    }
}
