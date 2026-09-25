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
        Fixtures.stubOnDemandViewportProbe(dataLoader: dataLoader)
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
        #expect(initial == 3)

        application.mapRegionManager.setMapLayerEnabled(false, id: StopsMapLayer.layerID)
        #expect(model.enabledLayerCount == 2)
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

    // MARK: - On-demand zones

    /// A ~100 km viewport over Alexandria, inside the zones layer's zoom window.
    private let alexandriaViewport = MKMapRect(
        origin: MKMapPoint(CLLocationCoordinate2D(latitude: 39.1, longitude: -77.6)),
        size: MKMapSize(width: 100_000, height: 100_000)
    )

    /// The panel has no `MKMapView`, so the zones reach its `Map` only through
    /// the model; without this the layer fetched on every pan and drew nothing.
    @Test func `A viewport fetch publishes the on-demand zones to the panel`() async throws {
        model.viewportDidChange(alexandriaViewport)
        await model.registrar.onDemandLayer?.fetchTask?.value

        #expect(model.onDemandZones.count == 1)
        #expect(model.onDemandMarkers.map(\.service.id) == ["5088_77652"])
        let marker = try #require(model.onDemandMarkers.first)
        #expect(model.onDemandMarker(withID: marker.id) === marker)
    }

    /// A zone marker tap pushes the service page through the sheet coordinator,
    /// like every other marker, at medium with a grabber.
    @Test func `A zone marker resolves to the service page's sheet route`() async throws {
        model.viewportDidChange(alexandriaViewport)
        await model.registrar.onDemandLayer?.fetchTask?.value
        let marker = try #require(model.onDemandMarkers.first)

        let route = try #require(model.onDemandServiceRoute(forMarkerID: marker.id))
        guard case .onDemandService(let service) = route else {
            Issue.record("expected an on-demand service route, got \(route.id)")
            return
        }
        #expect(service === marker.service)
        #expect(route.id == "onDemandService-5088_77652")
        #expect(route.prefersStacking)
        #expect(route.detentConfiguration.detents == [.medium, .large])
        #expect(route.detentConfiguration.initialDetent == .medium)
        #expect(route.detentConfiguration.showDragIndicator)

        model.viewportDidChange(MKMapRect(x: 0, y: 0, width: 5_000_000, height: 5_000_000))
        #expect(model.onDemandServiceRoute(forMarkerID: marker.id) == nil, "a marker that left the map resolves to nothing")
    }

    @Test func `Zooming out clears the panel's on-demand zones`() async {
        model.viewportDidChange(alexandriaViewport)
        await model.registrar.onDemandLayer?.fetchTask?.value
        #expect(!model.onDemandZones.isEmpty)

        model.viewportDidChange(MKMapRect(x: 0, y: 0, width: 5_000_000, height: 5_000_000))

        #expect(model.onDemandZones.isEmpty)
        #expect(model.onDemandMarkers.isEmpty)
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
}
