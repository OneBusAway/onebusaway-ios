//
//  SearchSheetViewModelTests.swift
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

/// The search session: what `MapFloatingPanelController` does for the UIKit panel.
@Suite(.serialized)
final class SearchSheetViewModelTests: OBATestCase {

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
    private func makeViewModel(dataLoader: MockDataLoader) -> (SearchSheetViewModel, Application, SheetCoordinator<AppSheetRoute>) {
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let displayModel = MapSearchDisplayModel()
        let router = SearchResultRouter(
            application: application,
            coordinator: coordinator,
            displayModel: displayModel,
            onPresentVehicleTrip: { _ in }
        )
        let viewModel = SearchSheetViewModel(application: application, coordinator: coordinator, router: router)
        return (viewModel, application, coordinator)
    }

    @Test @MainActor
    func `Typing rebuilds the interactor sections`() {
        let (viewModel, _, _) = makeViewModel(dataLoader: MockDataLoader(testName: name))

        viewModel.updateQuery("cap hill")

        #expect(viewModel.searchInteractor.sections.isEmpty == false)
    }

    /// Quick-search rows are only offered for vehicles when Obaco is running, which
    /// is what `isVehicleSearchAvailable` gates.
    @Test @MainActor
    func `Vehicle search availability mirrors the obaco feature`() {
        let (viewModel, application, _) = makeViewModel(dataLoader: MockDataLoader(testName: name))

        #expect(viewModel.isVehicleSearchAvailable == (application.features.obaco == .running))
    }

    @Test @MainActor
    func `Showing a stop pops search and pushes stop details`() async throws {
        let (viewModel, _, coordinator) = makeViewModel(dataLoader: MockDataLoader(testName: name))
        coordinator.push(.search)
        let stop = try #require(try Fixtures.loadSomeStops().first)

        viewModel.searchInteractor(viewModel.searchInteractor, showStop: stop)
        // `SearchDelegate` is synchronous, so presentation runs in a detached task.
        await viewModel.pendingPresentation?.value

        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.stackedRoutes.contains(.stopDetails(stopID: stop.id)))
    }

    @Test @MainActor
    func `Showing a map item records it as a recent search`() {
        let (viewModel, application, _) = makeViewModel(dataLoader: MockDataLoader(testName: name))
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))
        item.name = "Pike Place Market"

        viewModel.showMapItem(item)

        #expect(application.userDataStore.recentMapItems.isEmpty == false)
    }

    @Test @MainActor
    func `Clearing recent searches empties the store and rebuilds sections`() {
        let (viewModel, application, _) = makeViewModel(dataLoader: MockDataLoader(testName: name))
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))
        item.name = "Pike Place Market"
        application.userDataStore.addRecentMapItem(item)

        viewModel.confirmClearRecentSearches()

        #expect(application.userDataStore.recentMapItems.isEmpty)
    }

    /// A search that matches nothing raises a message, which the view turns into the
    /// same alert the UIKit path shows.
    @Test @MainActor
    func `A search with no results raises a no results message`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "routes_for_location_outofrange.json")) { request in
            request.url?.path.contains("/api/where/routes-for-location.json") ?? false
        }
        let (viewModel, _, coordinator) = makeViewModel(dataLoader: dataLoader)

        await viewModel.performSearchAndWait(request: SearchRequest(query: "zzzz", type: .route))

        #expect(viewModel.message?.kind == .noResults)
        #expect(coordinator.stackedRoutes.isEmpty)
    }

    /// The message carries a fresh identity per occurrence, so repeating a search
    /// that fails the same way twice raises two distinct values — otherwise, once
    /// the alert had been dismissed, the second failure would look like no change
    /// and never present.
    @Test @MainActor
    func `Repeating a failed search raises a distinct message each time`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "routes_for_location_outofrange.json")) { request in
            request.url?.path.contains("/api/where/routes-for-location.json") ?? false
        }
        let (viewModel, _, _) = makeViewModel(dataLoader: dataLoader)
        let request = SearchRequest(query: "zzzz", type: .route)

        await viewModel.performSearchAndWait(request: request)
        let first = try #require(viewModel.message)

        await viewModel.performSearchAndWait(request: request)
        let second = try #require(viewModel.message)

        #expect(first.text == second.text)
        #expect(first != second)
    }

    @Test @MainActor
    func `Typing clears a pending message`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "routes_for_location_outofrange.json")) { request in
            request.url?.path.contains("/api/where/routes-for-location.json") ?? false
        }
        let (viewModel, _, _) = makeViewModel(dataLoader: dataLoader)

        await viewModel.performSearchAndWait(request: SearchRequest(query: "zzzz", type: .route))
        #expect(viewModel.message != nil)

        viewModel.updateQuery("cap hill")

        #expect(viewModel.message == nil)
    }

    // MARK: - Outcome classification

    /// A `nil` response means the search never ran (no API service, no Obaco service,
    /// no map rect) — a different thing from a query that ran and matched nothing.
    /// Reporting the first as "no results" would send the user off rewording a query
    /// that never left the device.
    ///
    /// Asserted against the pure classifier because the `nil` case can't be produced
    /// through the test `Application`, which always has a region, an API service, and
    /// an Obaco service.
    @Test @MainActor
    func `A nil response is unavailable rather than no results`() {
        #expect(SearchSheetViewModel.SearchOutcome(response: nil) == .unavailable)
    }

    @Test @MainActor
    func `An empty response is no results`() {
        let response = SearchResponse(
            request: SearchRequest(query: "zzzz", type: .route),
            results: [],
            boundingRegion: nil,
            error: nil
        )

        #expect(SearchSheetViewModel.SearchOutcome(response: response) == .noResults)
    }

    @Test @MainActor
    func `One result routes straight through and several disambiguate`() throws {
        let stops = try Fixtures.loadSomeStops()
        let request = SearchRequest(query: "1", type: .stopNumber)

        let one = SearchResponse(request: request, results: Array(stops.prefix(1)), boundingRegion: nil, error: nil)
        let many = SearchResponse(request: request, results: Array(stops.prefix(3)), boundingRegion: nil, error: nil)

        #expect(SearchSheetViewModel.SearchOutcome(response: one) == .single(one))
        #expect(SearchSheetViewModel.SearchOutcome(response: many) == .disambiguate(many))
    }
}
