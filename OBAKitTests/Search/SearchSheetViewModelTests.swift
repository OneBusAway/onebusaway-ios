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
    func `Showing a map item records it as a recent search`() async {
        let (viewModel, application, _) = makeViewModel(dataLoader: MockDataLoader(testName: name))
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)))
        item.name = "Pike Place Market"

        viewModel.showMapItem(item)
        // The detached presentation task pops search and pushes the map item. The
        // suite is `.serialized`, so leaving it in flight lets it land during the
        // next test.
        await viewModel.pendingPresentation?.value

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

    // MARK: - Single-result sequencing

    /// A single result is resolved *before* search is left, so the sheet stack never
    /// sits empty across the network call and the user isn't dropped on home while a
    /// request is still in flight.
    @Test @MainActor
    func `A single result leaves search only once it resolves`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "routes-for-location-10.json")) { request in
            request.url?.path.contains("/api/where/routes-for-location.json") ?? false
        }
        dataLoader.mock(data: Fixtures.loadData(file: "stops-for-route-1_100002.json")) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (viewModel, _, coordinator) = makeViewModel(dataLoader: dataLoader)
        coordinator.push(.search)

        await viewModel.performSearchAndWait(request: SearchRequest(query: "10", type: .route))

        #expect(viewModel.message == nil)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.stackedRoutes.contains { if case .routeStops = $0 { return true } else { return false } })
    }

    /// The regression: search used to be popped *before* the route was resolved, so a
    /// failure set `message` on a view model whose view — and whose alert — had
    /// already been torn down. The user landed on home with no explanation. Search has
    /// to stay up so it can report the failure.
    @Test @MainActor
    func `A single result that fails to resolve keeps search up and reports the error`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "routes-for-location-10.json")) { request in
            request.url?.path.contains("/api/where/routes-for-location.json") ?? false
        }
        dataLoader.mock(data: "not json".data(using: .utf8)!) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (viewModel, _, coordinator) = makeViewModel(dataLoader: dataLoader)
        coordinator.push(.search)

        await viewModel.performSearchAndWait(request: SearchRequest(query: "10", type: .route))

        #expect(viewModel.message?.kind == .error)
        #expect(coordinator.currentRoute == .search, "Search must stay up to show the failure")
        #expect(coordinator.stackedRoutes.isEmpty)
    }

    // MARK: - Vehicle search

    /// The vehicle exists; its *details* request is what failed. `fetchVehicleID` used
    /// to swallow that and hand back an empty response, which classifies as
    /// `.noResults` — telling the user their query matched nothing and sending them
    /// off rewording a search that was fine. It has to read as the failure it is.
    @Test @MainActor
    func `A failed vehicle details fetch reports an error rather than no results`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let vehicles = #"[{"id": "1", "name": "Metro Transit", "vehicle_id": "1_4351"}]"#
        dataLoader.mock(data: Data(vehicles.utf8)) { request in
            request.url?.path.contains("/api/v1/regions/") ?? false
        }
        dataLoader.mock(data: "not json".data(using: .utf8)!) { request in
            request.url?.path.contains("/api/where/vehicle/") ?? false
        }
        let (viewModel, _, coordinator) = makeViewModel(dataLoader: dataLoader)

        await viewModel.performSearchAndWait(request: SearchRequest(query: "4351", type: .vehicleID))

        #expect(viewModel.message?.kind == .error)
        #expect(viewModel.message?.text != SearchSheetViewModel.noResultsText)
        #expect(coordinator.stackedRoutes.isEmpty)
    }

    // MARK: - Superseded searches

    /// Cancelling `searchTask` doesn't stop the request already in flight, so a
    /// superseded search runs to completion. It must not report, navigate, or clear
    /// `isSearching` — that flag belongs to the search that replaced it, and clearing
    /// it dismisses the progress HUD while the newer search is still running.
    @Test @MainActor
    func `A cancelled search neither reports nor navigates`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "routes_for_location_outofrange.json")) { request in
            request.url?.path.contains("/api/where/routes-for-location.json") ?? false
        }
        let (viewModel, _, coordinator) = makeViewModel(dataLoader: dataLoader)
        coordinator.push(.search)

        let search = Task { await viewModel.performSearchAndWait(request: SearchRequest(query: "zzzz", type: .route)) }
        search.cancel()
        await search.value

        #expect(viewModel.message == nil, "A search the user abandoned must not raise an alert")
        #expect(viewModel.isSearching, "Clearing this would dismiss the HUD out from under the newer search")
        #expect(coordinator.currentRoute == .search)
        #expect(coordinator.stackedRoutes.isEmpty)
    }

    // MARK: - Analytics

    /// The sheet system tears a sheet's content view down and rebuilds it without the
    /// user going anywhere, so `onAppear` can fire more than once per entry into
    /// search. The event is documented as once per entry.
    @Test @MainActor
    func `Reporting search opened more than once counts once`() throws {
        let (viewModel, application, _) = makeViewModel(dataLoader: MockDataLoader(testName: name))
        let analytics = try #require(application.analytics as? AnalyticsMock)

        viewModel.reportSearchOpened()
        viewModel.reportSearchOpened()
        viewModel.reportSearchOpened()

        let opens = analytics.reportedEvents.filter { $0.label == AnalyticsLabels.searchSelected }
        #expect(opens.count == 1)
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
