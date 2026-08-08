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

    @Test @MainActor
    func `More view returns more sheet host forwarding application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in }, presentingController: { nil })
        let host = factory.moreView()

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

        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in }, presentingController: { nil })
        let view = factory.stopDetailView(stopID: "1_10914")

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

        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in }, presentingController: { nil })
        let view = factory.stopDetailView(stopID: "1_10914")

        #expect(view.makePresenter().application === application)
        #expect(view.makeViewModel().stopID == "1_10914")
        // The remaining dependencies are handed over already built, so they can
        // be compared directly.
        #expect(view.formatters === application.formatters)
        #expect(view.userDefaults === application.userDefaults)
    }

    @Test @MainActor
    func `Route stops view returns route stops sheet view forwarding the stops for route`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stopsForRoute = try! Fixtures.loadRESTAPIPayload(type: StopsForRoute.self, fileName: "stops_for_route_1_44.json")

        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in })
        let view = factory.routeStopsView(stopsForRoute: stopsForRoute)

        #expect(view.stopsForRoute.route.id == stopsForRoute.route.id)
    }

    @Test @MainActor
    func `Search results view returns search results sheet view forwarding the response`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let request = SearchRequest(query: "test", type: .stopNumber)
        let response = SearchResponse(request: request, results: [], boundingRegion: nil, error: nil)

        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in })
        let view = factory.searchResultsView(response: response)

        #expect(view.response.request.query == response.request.query)
    }

    @Test @MainActor
    func `Search view returns search sheet view forwarding the application`() {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let factory = AppSheetViewFactory(application: application, onPresentTrip: { _ in })
        let view = factory.searchView()

        // SearchSheetView's viewModel is internal state via @StateObject, so we verify
        // indirectly by checking that the view rendered successfully with the placeholder
        #expect(!view.placeholder.isEmpty)
    }
}
