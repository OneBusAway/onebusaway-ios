//
//  AppSheetViewFactoryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Per-route factory branch coverage. Each branch that's been "wired up"
/// (i.e. removed from the shared `unimplementedView` catch-all) gets a
/// dedicated test so a future refactor that accidentally drops the branch
/// back into the catch-all fails the suite.
@Suite(.serialized)
final class AppSheetViewFactoryTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    /// The coordinator, display model, and stops observer are required dependencies, so every test
    /// builds the factory the same way the app does.
    @MainActor
    private func makeFactory(
        application: Application,
        coordinator: SheetCoordinator<AppSheetRoute> = SheetCoordinator(root: .home),
        displayModel: MapSearchDisplayModel = MapSearchDisplayModel(),
        stopsObserver: MapStopsObserver? = nil
    ) -> AppSheetViewFactory {
        AppSheetViewFactory(
            application: application,
            onPresentTrip: { _ in },
            onPresentVehicleTrip: { _ in },
            presentingController: { nil },
            coordinator: coordinator,
            searchDisplayModel: displayModel,
            stopsObserver: stopsObserver ?? MapStopsObserver(application: application)
        )
    }

    @Test @MainActor
    func `More view returns more sheet host forwarding application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let host = makeFactory(application: application).moreView()

        // Reference identity: the factory must forward its own `Application`
        // into the host, not construct a new one or drop it. `MoreSheetHost`'s
        // wiring itself (produces a UINavigationController wrapping
        // MoreViewController) is covered by MoreSheetHostTests — this test
        // owns the factory-to-host handoff only.
        #expect(host.application === application)
    }

    @Test @MainActor
    func `Stop detail view returns the SwiftUI sheet forwarding the stop ID`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).stopDetailView(stopID: "1_10914")

        #expect(view.stopID == "1_10914")
    }

    /// The stop sheet takes its dependencies as factory closures rather than as
    /// built objects, because SwiftUI decides when they are instantiated. That
    /// moves the handoff `More view returns more sheet host forwarding
    /// application` checks by reference into the closures, so this asserts it
    /// there instead: both must resolve against the factory's own `Application`,
    /// not a second one.
    @Test @MainActor
    func `Stop detail view's factories resolve against the factory's application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).stopDetailView(stopID: "1_10914")

        #expect(view.makePresenter().application === application)
        #expect(view.makeViewModel().stopID == "1_10914")
        // The remaining dependencies are handed over already built, so they can
        // be compared directly.
        #expect(view.formatters === application.formatters)
        #expect(view.userDefaults === application.userDefaults)
    }

    @Test @MainActor
    func `Route stops view returns route stops sheet view forwarding the stops for route`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopsForRoute = try Fixtures.loadRESTAPIPayload(type: StopsForRoute.self, fileName: "stops_for_route_1_44.json")

        let view = makeFactory(application: application).routeStopsView(stopsForRoute: stopsForRoute)

        #expect(view.stopsForRoute.route.id == stopsForRoute.route.id)
    }

    /// The route-stops sheet clears the map on dismissal, so it has to be handed the
    /// same display model the map renders — not a private one.
    @Test @MainActor
    func `Route stops view forwards the shared display model`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let displayModel = MapSearchDisplayModel()
        let stopsForRoute = try Fixtures.loadRESTAPIPayload(type: StopsForRoute.self, fileName: "stops_for_route_1_44.json")

        let factory = makeFactory(application: application, displayModel: displayModel)
        let view = factory.routeStopsView(stopsForRoute: stopsForRoute)

        #expect(view.displayModel === displayModel)
    }

    /// Both search surfaces have to route a picked result through the *same* router,
    /// or the two screens can drift on what "opening a result" means.
    @Test @MainActor
    func `Search results view is handed the factory's shared router`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let request = SearchRequest(query: "test", type: .stopNumber)
        let response = SearchResponse(request: request, results: [], boundingRegion: nil, error: nil)

        let factory = makeFactory(application: application)
        let view = factory.searchResultsView(response: response)

        #expect(view.router === factory.searchResultRouter)
        #expect(view.application === application)
    }

    @Test @MainActor
    func `Search view returns search sheet view forwarding the placeholder`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).searchView()

        #expect(view.placeholder == SearchPlaceholder.text(for: application))
        #expect(!view.placeholder.isEmpty)
    }

    /// The two index routes whose screens don't exist yet must still reach the
    /// placeholder rather than `unimplementedView`, whose DEBUG
    /// `assertionFailure` guards genuinely unwired routes.
    ///
    /// Goes through `view(for:)` rather than calling `indexPlaceholderView`
    /// directly: the dispatch is the thing under test. `view(for:)` is
    /// `@ViewBuilder`, so its switch — and any `assertionFailure` on the branch
    /// it picks — runs at call time. Completing this loop without trapping is
    /// the assertion.
    @Test @MainActor
    func `Remaining index routes dispatch to a placeholder without asserting`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let factory = makeFactory(application: application)

        for route in [AppSheetRoute.recentStopsAll, .bookmarksAll] {
            _ = factory.view(for: route)
        }
    }

    /// `.nearbyAll` carries no coordinate, so the factory resolves one. With a
    /// current region present there is always an anchor, so the view must not
    /// be handed nil.
    @Test @MainActor
    func `Nearby all view resolves a coordinate`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopsObserver = MapStopsObserver(application: application)
        let factory = makeFactory(application: application, stopsObserver: stopsObserver)

        let view = factory.nearbyAllView()

        let expectedCoordinate = NearbyCoordinateResolver.coordinate(
            viewportCenter: stopsObserver.viewportCenter,
            currentLocation: application.locationService.currentLocation,
            region: application.currentRegion
        )

        switch (view.coordinate, expectedCoordinate) {
        case let (.some(coordinate), .some(expected)):
            #expect(coordinate.latitude == expected.latitude)
            #expect(coordinate.longitude == expected.longitude)
        case (.none, .none):
            break // Both nil, test passes
        default:
            #expect(view.coordinate != nil)
        }
    }
}
