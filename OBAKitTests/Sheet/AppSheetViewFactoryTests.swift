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
import CoreLocation
import MapKit
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

    /// `.bookmarksAll` renders the native index, not the placeholder. With all
    /// three index routes wired, no route reaches `indexPlaceholderView` any
    /// more — it survives only as `unimplementedView`'s release-build fallback.
    @Test @MainActor
    func `Bookmarks all view forwards the application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).bookmarksAllView()

        #expect(view.application === application)
    }

    /// `.nearbyAll` carries no coordinate, so the factory resolves one from the
    /// map's settled viewport.
    ///
    /// Asserts against a *seeded* centre rather than against a second call to
    /// `NearbyCoordinateResolver` with the same inputs: recomputing the
    /// expectation the same way the factory does would pass even if the factory
    /// read the wrong sources — swapping location for region, or dropping the
    /// viewport entirely. `NearbyCoordinateResolverTests` covers the preference
    /// order; what's under test here is that the factory hands it the right
    /// three things.
    @Test @MainActor
    func `Nearby all view resolves the settled viewport center`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopsObserver = MapStopsObserver(application: application)

        // A deliberately implausible anchor: far from both the device location
        // and any region centre, so only the viewport could have produced it.
        let settled = CLLocationCoordinate2D(latitude: 12.345, longitude: 54.321)
        stopsObserver.updateViewport(
            MKCoordinateRegion(
                center: settled,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            )
        )
        try? #require(stopsObserver.viewportCenter != nil)

        let view = makeFactory(application: application, stopsObserver: stopsObserver).nearbyAllView()

        #expect(view.coordinate?.latitude == settled.latitude)
        #expect(view.coordinate?.longitude == settled.longitude)
    }

    /// With no viewport, no device fix, and no current region there is nothing to
    /// anchor on, and the factory must hand the view nil rather than a default —
    /// nil is what renders the empty state instead of fetching stops around (0, 0).
    @Test @MainActor
    func `Nearby all view passes nil when nothing can anchor the search`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopsObserver = MapStopsObserver(application: application)

        // `reset()` clears any settled centre; the test application has no
        // location fix. Only a current region could still supply an anchor.
        stopsObserver.reset()

        try? #require(stopsObserver.viewportCenter == nil)
        try? #require(application.locationService.currentLocation == nil)

        let view = makeFactory(application: application, stopsObserver: stopsObserver).nearbyAllView()

        if application.currentRegion == nil {
            #expect(view.coordinate == nil)
        } else {
            // A region is configured, so the last link in the chain supplies it.
            #expect(view.coordinate?.latitude == application.currentRegion?.centerCoordinate.latitude)
        }
    }

    /// `.nearbyStops` and `.nearbyAll` are the same screen; only the way the
    /// coordinate is obtained differs. This one carries its anchor in the route,
    /// so it must be passed through untouched.
    @Test @MainActor
    func `Nearby stops view forwards the route coordinate`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)

        let view = makeFactory(application: application).nearbyStopsView(coordinate: coordinate)

        #expect(view.coordinate?.latitude == coordinate.latitude)
        #expect(view.coordinate?.longitude == coordinate.longitude)
    }

    /// `.recentStopsAll` renders the native index, not the placeholder.
    @Test @MainActor
    func `Recent stops all view forwards the application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let view = makeFactory(application: application).recentStopsAllView()

        #expect(view.application === application)
    }
}
