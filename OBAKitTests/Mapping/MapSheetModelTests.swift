//
//  MapSheetModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// Spec 3.9: what the tile grid shows per group, and the unavailable rule.
@MainActor
@Suite(.serialized)
final class MapSheetModelTests: OBATestCase {

    private var application: Application!
    private var model: MapSheetModel!
    private var registrar: MapLayerRegistrar!

    override init() async throws {
        try await super.init()
        let dataLoader = MockDataLoader(testName: name)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.tampaRegion.OBABaseURL)
        Fixtures.stubOnDemandViewportProbe(dataLoader: dataLoader)
        application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        registrar = MapLayerRegistrar(application: application) { _ in }
        registrar.configure()
        model = MapSheetModel(mapRegionManager: application.mapRegionManager, mapViewModel: MapViewModel(application: application))
    }

    /// A layer whose availability the test controls.
    private final class StubLayer: NSObject, MapLayer {
        let id: String
        var availability: MapLayerAvailability
        init(id: String, availability: MapLayerAvailability) {
            self.id = id
            self.availability = availability
        }
        var title: String { id }
        var iconName: String { "questionmark" }
        var tintColor: UIColor { .black }
        var group: MapLayerGroup { .otherModes }
        var isEnabledByDefault: Bool { false }
        var zoomWindow: MapLayerZoomWindow { MapLayerZoomWindow(maxVisibleHeight: 1) }
        var densityBudget: Int { 1 }
        var isClusterable: Bool { false }
        var refreshPolicy: MapLayerRefreshPolicy { .static }
        var staleAfter: Duration? { nil }
        func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? { nil }
        func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }
        func activate() { }
        func deactivate() { }
        func viewportDidChange(_ mapRect: MKMapRect?) { }
        func mapAnnotationsWereCleared() { }
    }

    @Test func `Transit tiles are the registered transit layers in order and read On or Off`() {
        let tiles = model.tiles(in: .transit)
        #expect(tiles.map(\.id) == [StopsMapLayer.layerID, OnDemandMapLayer.layerID])
        #expect(tiles.map(\.iconName) == ["bus.fill", "car.fill"])
        #expect(tiles.allSatisfy { $0.isEnabled && $0.subtitle == Strings.mapLayersStateOn })

        model.toggle(tiles[1])
        #expect(model.tiles(in: .transit)[1].isEnabled == false)
        #expect(model.tiles(in: .transit)[1].subtitle == Strings.mapLayersStateOff)
        #expect(model.showsResetButton)
    }

    /// Tampa is a real list member with bikeshare disabled, so switching to it
    /// leaves no rental layers registered (the Puget Sound fixture has both).
    private func switchToRegionWithoutBikeshare() {
        application.regionsService.currentRegion = Fixtures.tampaRegion
        registrar.configure()
    }

    @Test func `The rentals group and chips are absent without rental layers`() {
        switchToRegionWithoutBikeshare()
        #expect(model.tiles(in: .otherModes).isEmpty)
        #expect(!model.showsRentalsGroup)
        #expect(!model.showsRangeChips)
    }

    @Test func `An unavailable tile can be switched off but not on`() {
        switchToRegionWithoutBikeshare()
        let stub = StubLayer(id: "stub", availability: .unavailable(reason: "Down"))
        application.mapRegionManager.registerMapLayer(stub)
        #expect(model.showsRentalsGroup)

        var tile = model.tiles(in: .otherModes).first { $0.id == "stub" }!
        #expect(tile.subtitle == "Down")
        #expect(!tile.isTapEnabled, "off and unavailable: cannot turn on")

        application.mapRegionManager.setMapLayerEnabled(true, id: "stub")
        tile = model.tiles(in: .otherModes).first { $0.id == "stub" }!
        #expect(tile.isEnabled)
        #expect(tile.isTapEnabled, "on and unavailable: can still be switched off")

        stub.availability = .unsupported
        #expect(model.tiles(in: .otherModes).isEmpty, "unsupported tiles are hidden")
        #expect(!model.showsRentalsGroup)
    }

    @Test func `Reset appears only when something differs from the defaults`() {
        #expect(!model.showsResetButton)
        model.setShowsPointsOfInterest(false)
        #expect(model.showsResetButton)
        model.resetToDefaults()
        #expect(!model.showsResetButton)
    }
}
