//
//  MapLayerViewportForwardingTests.swift
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

/// A layer that records every viewport it is handed, so the manager's zoom
/// gating can be asserted without a real data pipeline behind it.
@MainActor
private final class RecordingMapLayer: NSObject, MapLayer {
    let id: String
    let maxVisibleHeight: Double
    var receivedViewports: [MKMapRect?] = []

    init(id: String, maxVisibleHeight: Double) {
        self.id = id
        self.maxVisibleHeight = maxVisibleHeight
        super.init()
    }

    let title = "Recording"
    let iconName = "bus.fill"
    let tintColor: UIColor = .systemBlue
    let group: MapLayerGroup = .transit
    let isEnabledByDefault = true
    let availability: MapLayerAvailability = .available
    var zoomWindow: MapLayerZoomWindow { MapLayerZoomWindow(maxVisibleHeight: maxVisibleHeight) }
    let densityBudget = 100
    let isClusterable = false
    let refreshPolicy: MapLayerRefreshPolicy = .onViewportChange
    let staleAfter: Duration? = nil

    func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? { nil }
    func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }
    func activate() {}
    func deactivate() {}
    func viewportDidChange(_ mapRect: MKMapRect?) { receivedViewports.append(mapRect) }
    func mapAnnotationsWereCleared() {}
}

/// The panel drives the layer pipeline through `mapLayersViewportDidChange(_:)`
/// because the `MKMapView` this manager owns is never laid out in panel mode.
@MainActor
@Suite(.serialized)
final class MapLayerViewportForwardingTests: OBATestCase {

    private var manager: MapRegionManager!

    override init() async throws {
        try await super.init()
        let queue = OperationQueue()
        let dataLoader = MockDataLoader(testName: name)
        manager = MapRegionManager(application: buildApplication(queue: queue, dataLoader: dataLoader))
    }

    private func rect(height: Double) -> MKMapRect {
        MKMapRect(x: 0, y: 0, width: height, height: height)
    }

    @Test func `Forwards the viewport to an enabled layer inside its zoom window`() {
        let layer = RecordingMapLayer(id: "inside", maxVisibleHeight: 20_000)
        manager.registerMapLayer(layer)
        layer.receivedViewports.removeAll()

        manager.mapLayersViewportDidChange(rect(height: 10_000))

        #expect(layer.receivedViewports.count == 1)
        #expect(layer.receivedViewports.first??.height == 10_000)
    }

    @Test func `Passes nil when the viewport is outside the zoom window`() {
        let layer = RecordingMapLayer(id: "outside", maxVisibleHeight: 20_000)
        manager.registerMapLayer(layer)
        layer.receivedViewports.removeAll()

        manager.mapLayersViewportDidChange(rect(height: 50_000))

        #expect(layer.receivedViewports.count == 1)
        #expect(layer.receivedViewports.first! == nil)
    }

    @Test func `Skips disabled layers`() {
        let layer = RecordingMapLayer(id: "disabled", maxVisibleHeight: 20_000)
        manager.registerMapLayer(layer)
        manager.setMapLayerEnabled(false, id: "disabled")
        layer.receivedViewports.removeAll()

        manager.mapLayersViewportDidChange(rect(height: 10_000))

        #expect(layer.receivedViewports.isEmpty)
    }

    /// A layer registered *after* the panel reported a viewport must be primed
    /// with that viewport, not with the never-laid-out map view's rect.
    @Test func `Stores the rect so a later registration is primed with it`() {
        manager.mapLayersViewportDidChange(rect(height: 10_000))

        let layer = RecordingMapLayer(id: "late", maxVisibleHeight: 20_000)
        manager.registerMapLayer(layer)

        #expect(manager.currentVisibleMapRect.height == 10_000)
        #expect(layer.receivedViewports.first??.height == 10_000)
    }
}
