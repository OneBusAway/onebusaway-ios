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

    /// A search that matches nothing reports inline rather than popping an alert.
    @Test @MainActor
    func `A search with no results sets the no results message`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        dataLoader.mock(data: Fixtures.loadData(file: "routes_for_location_outofrange.json")) { request in
            request.url?.path.contains("/api/where/routes-for-location.json") ?? false
        }
        let (viewModel, _, coordinator) = makeViewModel(dataLoader: dataLoader)

        await viewModel.performSearchAndWait(request: SearchRequest(query: "zzzz", type: .route))

        #expect(viewModel.showsNoResults == true)
        #expect(coordinator.stackedRoutes.isEmpty)
    }
}
