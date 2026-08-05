//
//  MapLayerRendererDispatchTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class MapLayerRendererDispatchTests: OBATestCase {

    /// An overlay type only the stub layer recognizes.
    ///
    /// The explicit `nonisolated override init()` works around a Swift 6 quirk:
    /// with main-actor default isolation, a synthesized override of NSObject's
    /// `-init` picks up main-actor isolation, which then conflicts with the
    /// nonisolated Objective-C declaration it overrides.
    private final class StubOverlay: MKPolyline {
        nonisolated override init() {
            super.init()
        }
    }

    private final class StubLayer: NSObject, MapLayer {
        let id = "stub"
        let title = "Stub"
        let iconName = "circle"
        let tintColor = UIColor.systemPink
        let group = MapLayerGroup.transit
        let isEnabledByDefault = true
        let availability = MapLayerAvailability.available
        let zoomWindow = MapLayerZoomWindow(maxVisibleHeight: .greatestFiniteMagnitude)
        let densityBudget = 10
        let isClusterable = false
        let refreshPolicy = MapLayerRefreshPolicy.static
        let staleAfter: Duration? = nil

        private(set) var overlaysClearedCount = 0

        func annotationView(for annotation: MKAnnotation, in mapView: MKMapView) -> MKAnnotationView? { nil }
        func detailViewController(for annotation: MKAnnotation) -> UIViewController? { nil }
        func activate() { }
        func deactivate() { }
        func viewportDidChange(_ mapRect: MKMapRect?) { }
        func mapAnnotationsWereCleared() { }
        func mapOverlaysWereCleared() { overlaysClearedCount += 1 }

        func renderer(for overlay: MKOverlay, in mapView: MKMapView) -> MKOverlayRenderer? {
            guard let overlay = overlay as? StubOverlay else { return nil }
            let renderer = MKPolylineRenderer(polyline: overlay)
            renderer.lineWidth = 42
            return renderer
        }
    }

    private func makeCoordinates() -> [CLLocationCoordinate2D] {
        [CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
         CLLocationCoordinate2D(latitude: 47.7, longitude: -122.4)]
    }

    @Test func `A layer claims its own overlay before the generic polyline branch`() {
        let manager = MapRegionManager(application: buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: #function)))
        let layer = StubLayer()
        manager.registerMapLayer(layer)

        var coords = makeCoordinates()
        let overlay = StubOverlay(coordinates: &coords, count: coords.count)

        let renderer = manager.mapView(manager.mapView, rendererFor: overlay)

        // 42 proves the layer won, not the generic 3.0pt brand renderer.
        #expect((renderer as? MKPolylineRenderer)?.lineWidth == 42)
    }

    @Test func `An unrecognized overlay yields a renderer instead of trapping`() {
        let manager = MapRegionManager(application: buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: #function)))
        let circle = MKCircle(center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3), radius: 100)

        // Before the fix this call hits `fatalError()` and crashes the test run.
        let renderer = manager.mapView(manager.mapView, rendererFor: circle)

        #expect(renderer.overlay === circle)
    }

    @Test func `A wholesale overlay clear notifies the layer so it can re-add`() {
        let manager = MapRegionManager(application: buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: #function)))
        let layer = StubLayer()
        manager.registerMapLayer(layer)

        manager.cancelSearch()

        // Without this notification `mapOverlaysWereCleared()` is dead code and a
        // search cancellation silently erases the stop's route lines.
        #expect(layer.overlaysClearedCount == 1)
    }

    @Test func `A plain polyline still gets the brand renderer`() {
        let manager = MapRegionManager(application: buildApplication(queue: OperationQueue(), dataLoader: MockDataLoader(testName: #function)))
        var coords = makeCoordinates()
        let polyline = MKPolyline(coordinates: &coords, count: coords.count)

        let renderer = manager.mapView(manager.mapView, rendererFor: polyline)

        #expect((renderer as? MKPolylineRenderer)?.lineWidth == 3.0)
    }
}
