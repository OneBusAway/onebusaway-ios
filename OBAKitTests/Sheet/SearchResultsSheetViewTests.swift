//
//  SearchResultsSheetViewTests.swift
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

/// Everything the disambiguation sheet decides: which rows it builds, which failure
/// it surfaces inline, and the order in which selecting a row resolves, unwinds, and
/// presents. Asserted against the extracted pieces rather than a view host, the same
/// way `RouteStopsSheetViewTests` does.
@Suite(.serialized)
final class SearchResultsSheetViewTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    @MainActor
    private func makeApplication(dataLoader: MockDataLoader) -> Application {
        buildApplication(queue: queue, dataLoader: dataLoader)
    }

    @MainActor
    private func makeSelection(
        dataLoader: MockDataLoader
    ) -> (SearchResultsSelection, SheetCoordinator<AppSheetRoute>, MapSearchDisplayModel) {
        let application = makeApplication(dataLoader: dataLoader)
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let displayModel = MapSearchDisplayModel()
        let router = SearchResultRouter(
            application: application,
            coordinator: coordinator,
            displayModel: displayModel,
            onPresentVehicleTrip: { _ in }
        )
        return (SearchResultsSelection(router: router), coordinator, displayModel)
    }

    private func makeVehicle(id: String?, agency: String = "Metro Transit") throws -> AgencyVehicle {
        var dictionary: [String: Any] = ["id": "1", "name": agency]
        if let id { dictionary["vehicle_id"] = id }
        return try Fixtures.dictionaryToModel(type: AgencyVehicle.self, dictionary: dictionary)
    }

    // MARK: - Row mapping

    @Test @MainActor
    func `Rows carry one entry per result, keyed by the model's id`() throws {
        let application = makeApplication(dataLoader: MockDataLoader(testName: name))
        let stops = try Array(Fixtures.loadSomeStops().prefix(3))

        let rows = SearchResultRow.rows(
            for: stops,
            loadingVehicleID: nil,
            application: application,
            onSelectVehicle: { _ in },
            onSelect: { _ in }
        )

        #expect(rows.count == 3)
        #expect(rows.map(\.title) == stops.map(\.name))
        // Row identity comes from the stop id, not the title: two stops on opposite
        // sides of one corner share a name, which is exactly the case a
        // disambiguation list exists to handle.
        #expect(Set(rows.map(\.id)).count == 3)
        for (row, stop) in zip(rows, stops) {
            #expect(row.id.contains(stop.id))
        }
    }

    /// A vehicle needs a second request before it can be routed, so its row shows
    /// progress in place instead of navigating immediately.
    @Test @MainActor
    func `The vehicle being fetched becomes a loading row and the others stay tappable`() throws {
        let application = makeApplication(dataLoader: MockDataLoader(testName: name))
        let vehicles = [try makeVehicle(id: "1_1156"), try makeVehicle(id: "1_1157")]

        let rows = SearchResultRow.rows(
            for: vehicles,
            loadingVehicleID: "1_1156",
            application: application,
            onSelectVehicle: { _ in },
            onSelect: { _ in }
        )

        #expect(rows.count == 2)
        if case .loading = rows[0].kind {} else {
            Issue.record("The vehicle being fetched should render as a loading row")
        }
        #expect(rows[0].action == nil)

        if case .loading = rows[1].kind {
            Issue.record("Only the vehicle being fetched should render as a loading row")
        }
        #expect(rows[1].action != nil)
    }

    @Test @MainActor
    func `A tapped vehicle row selects by vehicle id rather than by result`() throws {
        let application = makeApplication(dataLoader: MockDataLoader(testName: name))
        let vehicle = try makeVehicle(id: "1_1156")
        var selectedVehicleID: String?
        var selectedResults = 0

        let rows = SearchResultRow.rows(
            for: [vehicle],
            loadingVehicleID: nil,
            application: application,
            onSelectVehicle: { selectedVehicleID = $0 },
            onSelect: { _ in selectedResults += 1 }
        )
        rows.first?.action?()

        #expect(selectedVehicleID == "1_1156")
        #expect(selectedResults == 0)
    }

    /// `AgencyVehicle.vehicleID` is optional, and a vehicle with no id can neither be
    /// fetched nor routed.
    @Test @MainActor
    func `A vehicle with no id produces no row`() throws {
        let application = makeApplication(dataLoader: MockDataLoader(testName: name))

        let rows = SearchResultRow.rows(
            for: [try makeVehicle(id: nil)],
            loadingVehicleID: nil,
            application: application,
            onSelectVehicle: { _ in },
            onSelect: { _ in }
        )

        #expect(rows.isEmpty)
    }

    @Test @MainActor
    func `A tapped non-vehicle row selects the result itself`() throws {
        let application = makeApplication(dataLoader: MockDataLoader(testName: name))
        let stop = try #require(try Fixtures.loadSomeStops().first)
        var selected: Stop?

        let rows = SearchResultRow.rows(
            for: [stop],
            loadingVehicleID: nil,
            application: application,
            onSelectVehicle: { _ in },
            onSelect: { selected = $0 as? Stop }
        )
        rows.first?.action?()

        #expect(selected === stop)
    }

    // MARK: - Inline error row

    @Test @MainActor
    func `No failure produces no error row`() {
        #expect(SearchResultRow.inlineErrorRow(
            vehicleError: nil,
            failedVehicleID: nil,
            selectionError: nil,
            failedResult: nil,
            onRetryVehicle: { _ in },
            onRetrySelect: { _ in }
        ) == nil)
    }

    @Test @MainActor
    func `A vehicle failure offers a retry for that vehicle`() throws {
        var retried: String?

        let row = try #require(SearchResultRow.inlineErrorRow(
            vehicleError: SearchError.noTripsAvailable,
            failedVehicleID: "1_1156",
            selectionError: nil,
            failedResult: nil,
            onRetryVehicle: { retried = $0 },
            onRetrySelect: { _ in }
        ))
        row.action?()

        #expect(row.title == SearchError.noTripsAvailable.localizedDescription)
        #expect(retried == "1_1156")
    }

    /// `selectVehicle` reports a missing API service without ever naming a vehicle, so
    /// there's nothing to retry — the row still has to say what went wrong.
    @Test @MainActor
    func `A vehicle failure with no vehicle id has no retry action`() throws {
        let row = try #require(SearchResultRow.inlineErrorRow(
            vehicleError: SearchError.noTripsAvailable,
            failedVehicleID: nil,
            selectionError: nil,
            failedResult: nil,
            onRetryVehicle: { _ in },
            onRetrySelect: { _ in }
        ))

        #expect(row.action == nil)
    }

    /// The regression this sheet shipped with: a failed resolve was dropped on the
    /// floor, so the tapped row simply did nothing — no error, no spinner, no
    /// navigation. It has to reach the same inline row a vehicle failure does.
    @Test @MainActor
    func `A failed resolve produces an error row that retries the same result`() throws {
        let stop = try #require(try Fixtures.loadSomeStops().first)
        var retried: Stop?

        let row = try #require(SearchResultRow.inlineErrorRow(
            vehicleError: nil,
            failedVehicleID: nil,
            selectionError: UnstructuredError("boom"),
            failedResult: stop,
            onRetryVehicle: { _ in },
            onRetrySelect: { retried = $0 as? Stop }
        ))
        row.action?()

        #expect(row.title == UnstructuredError("boom").localizedDescription)
        #expect(retried === stop)
    }

    /// Only one row is ever shown. A vehicle failure is the more specific of the two,
    /// and `selectVehicle` clears its own error before retrying, so it wins.
    @Test @MainActor
    func `A vehicle failure takes precedence over a resolve failure`() throws {
        let row = try #require(SearchResultRow.inlineErrorRow(
            vehicleError: SearchError.noTripsAvailable,
            failedVehicleID: "1_1156",
            selectionError: UnstructuredError("boom"),
            failedResult: "anything",
            onRetryVehicle: { _ in },
            onRetrySelect: { _ in }
        ))

        #expect(row.title == SearchError.noTripsAvailable.localizedDescription)
    }

    // MARK: - Selecting a row

    /// Resolve, then unwind, then present — and `popToRoot()` rather than a `pop()`
    /// per layer, because both the stacked results sheet and the `.search` route
    /// beneath it have to come off.
    @Test @MainActor
    func `Selecting a result unwinds to root and presents it`() async throws {
        let (selection, coordinator, displayModel) = makeSelection(dataLoader: MockDataLoader(testName: name))
        coordinator.push(.search)
        let stop = try #require(try Fixtures.loadSomeStops().first)
        coordinator.push(.searchResults(SearchResponse(
            request: SearchRequest(query: "1", type: .stopNumber),
            results: [stop],
            boundingRegion: nil,
            error: nil
        )))

        await selection.select(stop, coordinator: coordinator)

        #expect(selection.error == nil)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.stackedRoutes == [.stopDetails(stopID: stop.id)])
        #expect(displayModel.owner == .stopDetails(stopID: stop.id))
    }

    /// The Critical: `stops-for-route` fails, so there is nothing to show. The sheet
    /// has to stay up and say so rather than leave the row silently dead.
    @Test @MainActor
    func `A failed resolve keeps the sheet up and records the error and the result`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: "not json".data(using: .utf8)!) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (selection, coordinator, _) = makeSelection(dataLoader: dataLoader)
        coordinator.push(.search)
        let route = try Fixtures.createRoute(id: "1_100002")

        await selection.select(route, coordinator: coordinator)

        #expect(selection.error != nil)
        #expect((selection.failedResult as? Route) === route)
        #expect(coordinator.currentRoute == .search, "The results sheet must stay up to show the failure")
        #expect(coordinator.stackedRoutes.isEmpty)
    }

    /// `SearchResultRouter.resolve` returns nil with no `lastError` for a result type
    /// it doesn't handle. That's a programming error rather than anything the user
    /// did, but the row still can't be a no-op.
    @Test @MainActor
    func `An unhandled result type still reports an error`() async {
        let (selection, coordinator, _) = makeSelection(dataLoader: MockDataLoader(testName: name))

        await selection.select("not a search result", coordinator: coordinator)

        #expect(selection.error?.localizedDescription == SearchResultsSelection.unresolvableText)
        #expect(selection.failedResult != nil)
    }

    /// Retrying has to clear the previous failure, or the error row outlives the
    /// error and the sheet reports a failure that no longer happened.
    @Test @MainActor
    func `A successful retry clears the recorded failure`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: "not json".data(using: .utf8)!) { request in
            request.url?.path.contains("/api/where/stops-for-route") ?? false
        }
        let (selection, coordinator, _) = makeSelection(dataLoader: dataLoader)
        coordinator.push(.search)
        let route = try Fixtures.createRoute(id: "1_100002")

        await selection.select(route, coordinator: coordinator)
        #expect(selection.error != nil)

        dataLoader.replaceMappedResponses { loader in
            loader.mock(data: Fixtures.loadData(file: "stops-for-route-1_100002.json")) { request in
                request.url?.path.contains("/api/where/stops-for-route") ?? false
            }
        }

        await selection.select(route, coordinator: coordinator)

        #expect(selection.error == nil)
        #expect(selection.failedResult == nil)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.stackedRoutes.contains { if case .routeStops = $0 { return true } else { return false } })
    }
}
