//
//  SearchResultRouterTests.swift
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

/// Turning one search result into a map display plus a sheet route.
@Suite(.serialized)
final class SearchResultRouterTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @MainActor
    private func makeRouter(
        dataLoader: MockDataLoader,
        onPresentVehicleTrip: @escaping (VehicleStatus) -> Void = { _ in }
    ) -> (SearchResultRouter, SheetCoordinator<AppSheetRoute>, MapSearchDisplayModel) {
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let displayModel = MapSearchDisplayModel()
        let router = SearchResultRouter(
            application: application,
            coordinator: coordinator,
            displayModel: displayModel,
            onPresentVehicleTrip: onPresentVehicleTrip
        )
        return (router, coordinator, displayModel)
    }

    @Test @MainActor
    func `A stop result pushes stop details and centers the map`() async throws {
        let (router, coordinator, displayModel) = makeRouter(dataLoader: MockDataLoader(testName: name))
        let stop = try #require(try Fixtures.loadSomeStops().first)

        await router.present(result: stop)

        #expect(coordinator.stackedRoutes.contains(.stopDetails(stopID: stop.id)))
        if case .stop = displayModel.display {} else {
            Issue.record("Expected the stop to be displayed on the map")
        }
    }

    @Test @MainActor
    func `A map item result pushes the map item sheet and centers the map`() async {
        let (router, coordinator, displayModel) = makeRouter(dataLoader: MockDataLoader(testName: name))
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))

        await router.present(result: item)

        #expect(coordinator.stackedRoutes.contains(.mapItem(item)))
        if case .mapItem = displayModel.display {} else {
            Issue.record("Expected the map item to be displayed on the map")
        }
    }

    /// A `Route` isn't renderable on its own — it has to be resolved into
    /// `StopsForRoute` first, which is where the polyline and stop list come from.
    @Test @MainActor
    func `A route result resolves stops for route then pushes the route stops sheet`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_route_1_44.json")) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (router, coordinator, displayModel) = makeRouter(dataLoader: dataLoader)
        let route = try Fixtures.createRoute(id: "1_44")

        await router.present(result: route)

        #expect(coordinator.stackedRoutes.contains { if case .routeStops = $0 { return true } else { return false } })
        #expect(displayModel.suppressesAmbientStops == true)
        #expect(router.lastError == nil)
    }

    /// The map display is cleared when its owning route leaves the sheet stack, so
    /// the route recorded as the owner has to be the very one that got pushed. If
    /// the two drift, the display is either wiped while its sheet is still up or
    /// stranded on the map after it goes away.
    @Test @MainActor
    func `The recorded display owner is the route that was pushed`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_route_1_44.json")) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (router, coordinator, displayModel) = makeRouter(dataLoader: dataLoader)
        let route = try Fixtures.createRoute(id: "1_44")

        await router.present(result: route)

        #expect(displayModel.owner == coordinator.stackedRoutes.last)
    }

    /// Stops and map items own their displays too — the map-item sheet no longer
    /// clears the marker from its own `onDisappear`.
    @Test @MainActor
    func `A map item result owns its display`() async {
        let (router, coordinator, displayModel) = makeRouter(dataLoader: MockDataLoader(testName: name))
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))

        await router.present(result: item)

        #expect(displayModel.owner == .mapItem(item))
        #expect(displayModel.owner == coordinator.stackedRoutes.last)
    }

    @Test @MainActor
    func `A failed route resolution records the error and pushes nothing`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: "not json".data(using: .utf8)!) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (router, coordinator, _) = makeRouter(dataLoader: dataLoader)
        let route = try Fixtures.createRoute(id: "1_44")

        await router.present(result: route)

        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(router.lastError != nil)
    }

    // MARK: - Resolve / present split

    /// Resolving performs the network work but touches nothing on screen, so callers
    /// can keep their own UI up (and report a failure there) before committing to the
    /// navigation.
    @Test @MainActor
    func `Resolving leaves the sheet stack and the map untouched`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_route_1_44.json")) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (router, coordinator, displayModel) = makeRouter(dataLoader: dataLoader)
        let route = try Fixtures.createRoute(id: "1_44")

        let resolved = await router.resolve(result: route)

        #expect(resolved != nil)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(displayModel.owner == nil)
        if case .none = displayModel.display {} else {
            Issue.record("Resolving must not draw anything, got \(displayModel.display)")
        }
    }

    /// Drawing and pushing happen in one synchronous step, so the stacked layer never
    /// sits empty between them.
    @Test @MainActor
    func `Presenting a resolution draws it and pushes its sheet together`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_route_1_44.json")) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (router, coordinator, displayModel) = makeRouter(dataLoader: dataLoader)
        let route = try Fixtures.createRoute(id: "1_44")
        let resolved = try #require(await router.resolve(result: route))

        router.present(resolved)

        #expect(displayModel.suppressesAmbientStops == true)
        #expect(displayModel.owner == coordinator.stackedRoutes.last)
    }

    @Test @MainActor
    func `A failed resolution yields nothing and records the error`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: "not json".data(using: .utf8)!) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (router, coordinator, _) = makeRouter(dataLoader: dataLoader)
        let route = try Fixtures.createRoute(id: "1_44")

        let resolved = await router.resolve(result: route)

        #expect(resolved == nil)
        #expect(router.lastError != nil)
        #expect(coordinator.stackedRoutes.isEmpty)
    }

    @Test @MainActor
    func `Resolving a single result returns nil when the response holds several`() async throws {
        let (router, coordinator, _) = makeRouter(dataLoader: MockDataLoader(testName: name))
        let stops = try Fixtures.loadSomeStops()
        let response = SearchResponse(
            request: SearchRequest(query: "1", type: .stopNumber),
            results: Array(stops.prefix(3)),
            boundingRegion: nil,
            error: nil
        )

        let resolved = await router.resolveSingleResult(from: response)

        #expect(resolved == nil)
        #expect(coordinator.stackedRoutes.isEmpty)
    }
}
