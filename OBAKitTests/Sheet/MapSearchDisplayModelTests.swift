//
//  MapSearchDisplayModelTests.swift
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

/// Map-side state for a displayed search result: what to draw and where to point
/// the camera.
@MainActor
@Suite(.serialized)
final class MapSearchDisplayModelTests {

    private func makeMapItem(latitude: Double = 47.6, longitude: Double = -122.3) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
    }

    @Test func `Starts with nothing displayed`() {
        let model = MapSearchDisplayModel()

        #expect(model.cameraTarget == nil)
        #expect(model.suppressesAmbientStops == false)
        if case .none = model.display {} else {
            Issue.record("Expected .none, got \(model.display)")
        }
    }

    @Test func `Showing a map item targets its coordinate`() throws {
        let model = MapSearchDisplayModel()
        model.show(mapItem: makeMapItem(), animated: true)

        guard case .mapItem = model.display else {
            Issue.record("Expected .mapItem, got \(model.display)")
            return
        }
        guard case .coordinate(let coordinate, let animated) = try #require(model.cameraTarget) else {
            Issue.record("Expected a coordinate target")
            return
        }
        #expect(coordinate.latitude == 47.6)
        #expect(animated == true)
    }

    @Test func `Showing a route targets its bounding rect and suppresses ambient stops`() throws {
        let model = MapSearchDisplayModel()
        let stopsForRoute = try Fixtures.loadRESTAPIPayload(type: StopsForRoute.self, fileName: "stops_for_route_1_44.json")

        model.show(stopsForRoute: stopsForRoute)

        #expect(model.suppressesAmbientStops == true)
        guard case .route(let display) = model.display else {
            Issue.record("Expected .route, got \(model.display)")
            return
        }
        #expect(display.polylines.isEmpty == false)
        guard case .rect = try #require(model.cameraTarget) else {
            Issue.record("Expected a rect target")
            return
        }
    }

    /// The camera target is one-shot: the view applies it and consumes it, so an
    /// unrelated body evaluation later can't yank the map back.
    @Test func `Consuming the camera target clears it without clearing the display`() {
        let model = MapSearchDisplayModel()
        model.show(mapItem: makeMapItem(), animated: false)

        model.consumeCameraTarget()

        #expect(model.cameraTarget == nil)
        if case .mapItem = model.display {} else {
            Issue.record("Consuming the camera target must not clear the display")
        }
    }

    @Test func `Clearing resets display and camera target`() throws {
        let model = MapSearchDisplayModel()
        let stopsForRoute = try Fixtures.loadRESTAPIPayload(type: StopsForRoute.self, fileName: "stops_for_route_1_44.json")
        model.show(stopsForRoute: stopsForRoute)

        model.clear()

        #expect(model.cameraTarget == nil)
        #expect(model.suppressesAmbientStops == false)
        if case .none = model.display {} else {
            Issue.record("Expected .none after clear")
        }
    }
}
