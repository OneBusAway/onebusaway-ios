//
//  MapPanelLayersModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import Foundation
import MapKit
import Testing
import OTPKit
@testable import OBAKit
@testable import OBAKitCore

/// The panel's window onto the layer system. `MapSheetView` writes through
/// `MapRegionManager`, which posts notifications; this model is what turns those
/// into published state the SwiftUI map re-renders from.
@MainActor
@Suite(.serialized)
final class MapPanelLayersModelTests: OBATestCase {

    private var application: Application!
    private var model: MapPanelLayersModel!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        // The no-bikeshare case below switches to Tampa, which fetches against
        // that region's base URL.
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.tampaRegion.OBABaseURL)
        application = buildApplication(queue: queue, dataLoader: dataLoader)
        model = MapPanelLayersModel(application: application)
    }

    @Test func `Registers the stops layer on construction`() {
        #expect(application.mapRegionManager.mapLayer(id: StopsMapLayer.layerID) != nil)
        #expect(model.isStopsLayerEnabled)
    }

    @Test func `Tracks the stops layer being switched off`() {
        application.mapRegionManager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)

        #expect(model.isStopsLayerEnabled == false)
    }

    @Test func `Tracks the stops layer being switched back on`() {
        application.mapRegionManager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)
        application.mapRegionManager.setMapLayerEnabled(true, id: StopsMapLayer.layerID)

        #expect(model.isStopsLayerEnabled)
    }

    @Test func `Points of interest default to on`() {
        #expect(model.showsPointsOfInterest)
    }

    @Test func `Tracks points of interest being switched off`() {
        application.mapRegionManager.mapViewShowsPointsOfInterest = false

        #expect(model.showsPointsOfInterest == false)
    }

    /// The badge is the panel's only at-a-glance readout of layer state, so it
    /// has to move with the toggles.
    @Test func `Badge count follows enabled layers`() {
        let initial = model.enabledLayerCount
        #expect(initial == 2)

        application.mapRegionManager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)
        #expect(model.enabledLayerCount == 1)
    }

    /// Reset restores stops on and points of interest on in one write; the model
    /// must reflect both.
    @Test func `Reflects a reset to defaults`() {
        application.mapRegionManager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)
        application.mapRegionManager.mapViewShowsPointsOfInterest = false

        application.mapRegionManager.resetMapLayersToDefaults()

        #expect(model.isStopsLayerEnabled)
        #expect(model.showsPointsOfInterest)
    }

    @Test func `Forwards the viewport to the layer pipeline`() {
        let rect = MKMapRect(x: 0, y: 0, width: 10_000, height: 10_000)

        model.viewportDidChange(rect)

        #expect(application.mapRegionManager.currentVisibleMapRect.height == 10_000)
    }

    /// Leaving bikeshare must *empty* the panel, or the rider keeps seeing the
    /// old region's vehicles. Pins the whole chain — layer deactivation clears
    /// `visibleRentals` through the still-live subscription, then the coordinator
    /// drops — because no single link does it alone.
    ///
    /// Seeded first on purpose: `rentalItems` is empty at construction in every
    /// scenario, so asserting only the empty state would pass with the feature
    /// deleted.
    @Test func `Leaving a bikeshare region clears the published rentals`() throws {
        _ = try seedRentals()
        #expect(model.rentalItems.isEmpty == false)
        #expect(model.rental(withID: "near") != nil)

        // Tampa is a real list member with bikeshare disabled.
        application.regionsService.currentRegion = Fixtures.tampaRegion

        #expect(model.registrar.rentalCoordinator == nil)
        #expect(model.rentalItems.isEmpty)
        #expect(model.rental(withID: "near") == nil)
    }

    /// The two rental sheet routes carry ids, not model objects, so the model
    /// has to resolve them — and answer nil once a vehicle leaves the feed.
    @Test func `Resolving an unknown rental id returns nil`() {
        #expect(model.rental(withID: "not-in-the-feed") == nil)
    }

    @Test func `Resolving unknown rental ids drops them`() {
        #expect(model.rentals(withIDs: ["a", "b"]).isEmpty)
    }

    // MARK: - Range filter

    /// Puts two bikes on the panel, one either side of the threshold used below.
    private func seedRentals() throws -> RentalLayerCoordinator {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "near", formFactor: "BICYCLE", rangeMeters: 3_000),
            try RentalFixtures.vehicle(id: "far", formFactor: "BICYCLE", rangeMeters: 12_000)
        ]))
        return coordinator
    }

    /// Regression: `MapSheetView` writes the threshold through
    /// `MapRegionManager` and posts `.rentalRangeFilterDidChange`, but the panel
    /// only re-read its own published flags in response. The filter persisted and
    /// did nothing to the map until the next region change or launch.
    @Test func `Raising the range filter hides short range vehicles from the panel`() throws {
        _ = try seedRentals()
        #expect(model.rentals(withIDs: ["near", "far"]).count == 2)

        application.mapRegionManager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)

        #expect(model.rentals(withIDs: ["near", "far"]).map(\.id) == ["far"])
        #expect(model.rental(withID: "near") == nil)
    }

    /// The same gap hit Reset, which sets the filter back to `.any`.
    @Test func `Resetting to defaults restores vehicles the filter had hidden`() throws {
        _ = try seedRentals()
        application.mapRegionManager.rentalRangeFilter = RentalRangeFilter(minimumRangeMeters: 8047)
        #expect(model.rental(withID: "near") == nil)

        application.mapRegionManager.resetMapLayersToDefaults()

        #expect(model.rentals(withIDs: ["near", "far"]).map(\.id) == ["far", "near"])
    }

    // MARK: - Clustering geometry

    /// The panel learns its size from `.onGeometryChange`, which can report a
    /// first non-zero size *after* the camera has settled. Clustering has to
    /// recompute when that happens, or the first screen stays unclustered until
    /// the rider moves the map.
    @Test func `A map size arriving after the camera clusters the rentals`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "a", formFactor: "BICYCLE", lat: 47.60000, lon: -122.30000),
            try RentalFixtures.vehicle(id: "b", formFactor: "BICYCLE", lat: 47.60001, lon: -122.30001)
        ]))

        let mapRect = MKMapRect(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))

        // Camera settles first, before any layout has been reported.
        model.updateViewport(mapRect: mapRect, mapSize: .zero)
        #expect(model.rentalItems.count == 2)

        model.updateMapSize(CGSize(width: 390, height: 844))

        #expect(model.rentalItems.count == 1)
    }

    /// A camera settle that lands on the same clustering must not republish.
    ///
    /// `recomputeClusters()` runs on every settle, and `@Published` fires on
    /// assignment rather than on difference — so writing an identical array
    /// re-rendered the whole panel body, `factory.view(for:)` included, for a
    /// pan that moved no marker. Panning inside one grid cell is the common case.
    ///
    /// The second half is what keeps this from passing on a model that publishes
    /// nothing at all: a real change still has to come through.
    @Test func `An unchanged recompute publishes nothing`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "a", formFactor: "BICYCLE", lat: 47.60000, lon: -122.30000)
        ]))

        let mapRect = MKMapRect(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        let mapSize = CGSize(width: 390, height: 844)
        model.updateViewport(mapRect: mapRect, mapSize: mapSize)

        var publishCount = 0
        let subscription = model.$rentalItems.dropFirst().sink { _ in publishCount += 1 }
        defer { subscription.cancel() }

        // Same viewport, same rentals: the computed array is identical.
        model.updateViewport(mapRect: mapRect, mapSize: mapSize)
        #expect(publishCount == 0)

        // A vehicle actually arriving still has to reach the panel.
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "b", formFactor: "BICYCLE", lat: 47.60300, lon: -122.30300)
        ]))
        #expect(publishCount == 1)
        // Asserted through `members` rather than item count, so the test does not
        // depend on whether the two land in the same grid cell.
        #expect(model.rentalItems.flatMap(\.members).map(\.id).sorted() == ["a", "b"])
    }

    // MARK: - Resolution while the feed is silent

    /// Regression: framing a planned trip zooms the map out past the rental layer's
    /// `zoomWindow`, so `MapRegionManager.forwardViewport(to:)` hands the coordinator a nil
    /// viewport and `visibleRentals` empties wholesale. The rental sheets stacked under the
    /// trip planner resolve their ids on every body pass, so they all flipped to their
    /// "not available" state — the rider ended a trip, dismissed the planner, and found two
    /// dead sheets underneath. A rider pinching out with a rental sheet open hit the same
    /// thing without any trip involved.
    @Test func `A closed zoom gate does not make an open sheet's vehicle unresolvable`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.viewportDidChange(TestData.seattleMapRect)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "b7", formFactor: "BICYCLE")
        ]))
        #expect(model.rental(withID: "b7") != nil)

        // The gate closing empties the feed: the next fetch reports nothing in view.
        coordinator.viewportDidChange(nil)
        coordinator.apply(RentalFixtures.snapshot(removed: ["b7"]))
        #expect(coordinator.visibleRentals.isEmpty)

        #expect(coordinator.isReportingVehicles == false)
        #expect(model.rental(withID: "b7") != nil)
        #expect(model.rentals(withIDs: ["b7"]).map(\.id) == ["b7"])
    }

    /// The fallback must not reach the map: a vehicle the feed is no longer reporting has
    /// no business being drawn at a viewport it was never fetched for.
    @Test func `The dormant-feed fallback never redraws vehicles on the map`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.viewportDidChange(TestData.seattleMapRect)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "b7", formFactor: "BICYCLE")
        ]))
        #expect(model.rentalItems.isEmpty == false)

        coordinator.viewportDidChange(nil)
        coordinator.apply(RentalFixtures.snapshot(removed: ["b7"]))

        #expect(model.rental(withID: "b7") != nil)
        #expect(model.rentalItems.isEmpty)
    }

    /// The narrow half of the rule: while the feed *is* reporting, a vehicle missing from
    /// it really is gone. Saying so is the whole point of resolving by id instead of
    /// carrying the model in the route.
    @Test func `A vehicle that leaves a live feed still resolves to nil`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.viewportDidChange(TestData.seattleMapRect)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "b7", formFactor: "BICYCLE"),
            try RentalFixtures.vehicle(id: "b8", formFactor: "BICYCLE")
        ]))
        #expect(model.rental(withID: "b7") != nil)

        coordinator.apply(RentalFixtures.snapshot(removed: ["b7"]))

        #expect(coordinator.isReportingVehicles)
        #expect(model.rental(withID: "b7") == nil)
        #expect(model.rental(withID: "b8") != nil)
    }

    // MARK: - Pinned vehicles

    /// Regression, second half: the feed is still reporting, but from a viewport that no
    /// longer holds this vehicle — which is what framing a planned trip does, since the
    /// re-fetch for the itinerary's bounding box returns every bike outside it as a
    /// removal. `lastReportedRentals` cannot help (the live list is non-empty, just
    /// without this one), so the rental sheets stacked under the planner still died.
    @Test func `A pinned vehicle survives the viewport moving off it`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.viewportDidChange(TestData.seattleMapRect)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "b7", formFactor: "BICYCLE")
        ]))

        let opened = try #require(model.rental(withID: "b7"))
        model.pinForOpenSheet([opened])

        // The map moves; the re-fetch reports a different set entirely.
        coordinator.apply(RentalFixtures.snapshot(
            added: [try RentalFixtures.vehicle(id: "elsewhere", formFactor: "BICYCLE")],
            removed: ["b7"]
        ))

        #expect(coordinator.isReportingVehicles)
        #expect(coordinator.visibleRentals.map(\.id) == ["elsewhere"])
        #expect(model.rental(withID: "b7")?.id == "b7")
        #expect(model.rentals(withIDs: ["b7"]).map(\.id) == ["b7"])
    }

    /// Pinning must not freeze the sheet: the live list still answers first, so range and
    /// position keep updating under an open sheet as the feed refreshes.
    @Test func `A live report still wins over a pin`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.viewportDidChange(TestData.seattleMapRect)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "b7", formFactor: "BICYCLE", batteryPercent: 0.2)
        ]))
        model.pinForOpenSheet([try #require(model.rental(withID: "b7"))])

        coordinator.apply(RentalFixtures.snapshot(updated: [
            try RentalFixtures.vehicle(id: "b7", formFactor: "BICYCLE", batteryPercent: 0.9)
        ]))

        #expect(model.rental(withID: "b7")?.batteryPercent == 0.9)
    }

    /// A pin is not a licence to draw: `rentalItems` still comes from the live list alone,
    /// so a pinned vehicle is never painted at a viewport it was not fetched for.
    @Test func `A pinned vehicle is never drawn on the map`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.viewportDidChange(TestData.seattleMapRect)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "b7", formFactor: "BICYCLE")
        ]))
        model.pinForOpenSheet([try #require(model.rental(withID: "b7"))])

        coordinator.apply(RentalFixtures.snapshot(removed: ["b7"]))

        #expect(model.rental(withID: "b7") != nil)
        #expect(model.rentalItems.flatMap(\.members).isEmpty)
    }

    /// A vehicle nobody opened a sheet for is still allowed to be gone — pinning widens
    /// the answer only for the sheets that need it.
    @Test func `An unpinned vehicle that leaves a live feed still resolves to nil`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.viewportDidChange(TestData.seattleMapRect)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "b7", formFactor: "BICYCLE"),
            try RentalFixtures.vehicle(id: "b8", formFactor: "BICYCLE")
        ]))
        model.pinForOpenSheet([try #require(model.rental(withID: "b7"))])

        coordinator.apply(RentalFixtures.snapshot(removed: ["b7", "b8"]))

        #expect(model.rental(withID: "b7") != nil)
        #expect(model.rental(withID: "b8") == nil)
    }

    /// The cluster list keeps its order as members drop out of the viewport, so rows do
    /// not reshuffle under the rider's finger.
    @Test func `A partially pinned cluster resolves every member in route order`() throws {
        let coordinator = try #require(model.registrar.rentalCoordinator)
        coordinator.setLayer(id: RentalMapLayer.bikesLayerID, enabled: true, formFactors: [.bicycle])
        coordinator.viewportDidChange(TestData.seattleMapRect)
        coordinator.apply(RentalFixtures.snapshot(added: [
            try RentalFixtures.vehicle(id: "a", formFactor: "BICYCLE"),
            try RentalFixtures.vehicle(id: "b", formFactor: "BICYCLE")
        ]))
        model.pinForOpenSheet(model.rentals(withIDs: ["a", "b"]))

        coordinator.apply(RentalFixtures.snapshot(removed: ["a"]))

        #expect(model.rentals(withIDs: ["a", "b"]).map(\.id) == ["b", "a"])
        #expect(model.rentals(withIDs: ["a", "b"]).count == 2)
    }
}
