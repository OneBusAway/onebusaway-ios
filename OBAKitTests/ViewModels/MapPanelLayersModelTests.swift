//
//  MapPanelLayersModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
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
}
