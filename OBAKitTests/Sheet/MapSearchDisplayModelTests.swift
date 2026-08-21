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

    private func loadStopsForRoute() throws -> StopsForRoute {
        try Fixtures.loadRESTAPIPayload(type: StopsForRoute.self, fileName: "stops_for_route_1_44.json")
    }

    @Test func `Showing a map item targets its coordinate`() throws {
        let item = makeMapItem()
        let model = MapSearchDisplayModel()
        model.show(mapItem: item, animated: true, owner: .mapItem(item))

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
        let stopsForRoute = try loadStopsForRoute()

        model.show(stopsForRoute: stopsForRoute, owner: .routeStops(stopsForRoute))

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
        let item = makeMapItem()
        let model = MapSearchDisplayModel()
        model.show(mapItem: item, animated: false, owner: .mapItem(item))

        model.consumeCameraTarget()

        #expect(model.cameraTarget == nil)
        if case .mapItem = model.display {} else {
            Issue.record("Consuming the camera target must not clear the display")
        }
    }

    @Test func `Clearing resets display, camera target, and owner`() throws {
        let model = MapSearchDisplayModel()
        let stopsForRoute = try loadStopsForRoute()
        model.show(stopsForRoute: stopsForRoute, owner: .routeStops(stopsForRoute))

        model.clear()

        #expect(model.cameraTarget == nil)
        #expect(model.owner == nil)
        #expect(model.suppressesAmbientStops == false)
        if case .none = model.display {} else {
            Issue.record("Expected .none after clear")
        }
    }

    // MARK: - Ownership

    @Test func `Showing a result records the sheet route that owns it`() throws {
        let model = MapSearchDisplayModel()
        let stopsForRoute = try loadStopsForRoute()

        model.show(stopsForRoute: stopsForRoute, owner: .routeStops(stopsForRoute))

        #expect(model.owner == .routeStops(stopsForRoute))
    }

    /// The regression this ownership rule exists for: the route sheet's view can be
    /// torn down and rebuilt by the sheet system without the sheet being dismissed.
    /// Keying the polyline's lifetime to the view's `onDisappear` wiped the route off
    /// the map seconds after it was drawn; keying it to the route stack does not.
    @Test func `The display survives while its owning route is still on the stack`() throws {
        let model = MapSearchDisplayModel()
        let stopsForRoute = try loadStopsForRoute()
        model.show(stopsForRoute: stopsForRoute, owner: .routeStops(stopsForRoute))

        model.clearIfOwnerAbsent(from: [.home, .routeStops(stopsForRoute)])

        #expect(model.suppressesAmbientStops == true)
        if case .route = model.display {} else {
            Issue.record("Expected the route to survive, got \(model.display)")
        }
    }

    /// Tapping a stop out of the route's list stacks `.stopDetails` over the route
    /// sheet rather than replacing it, so the polyline has to stay drawn beneath.
    @Test func `Stacking stop details over the route keeps the route drawn`() throws {
        let model = MapSearchDisplayModel()
        let stopsForRoute = try loadStopsForRoute()
        let stopID = try #require(stopsForRoute.stops?.first?.id)
        model.show(stopsForRoute: stopsForRoute, owner: .routeStops(stopsForRoute))

        model.clearIfOwnerAbsent(from: [.home, .routeStops(stopsForRoute), .stopDetails(stopID: stopID)])

        if case .route = model.display {} else {
            Issue.record("Expected the route to survive, got \(model.display)")
        }
    }

    @Test func `The display clears once its owning route leaves the stack`() throws {
        let model = MapSearchDisplayModel()
        let stopsForRoute = try loadStopsForRoute()
        model.show(stopsForRoute: stopsForRoute, owner: .routeStops(stopsForRoute))

        model.clearIfOwnerAbsent(from: [.home])

        #expect(model.owner == nil)
        #expect(model.suppressesAmbientStops == false)
        if case .none = model.display {} else {
            Issue.record("Expected .none once the owning route was popped")
        }
    }

    @Test func `Checking ownership with nothing displayed is a no-op`() {
        let model = MapSearchDisplayModel()

        model.clearIfOwnerAbsent(from: [])

        #expect(model.owner == nil)
        if case .none = model.display {} else {
            Issue.record("Expected .none")
        }
    }
}
