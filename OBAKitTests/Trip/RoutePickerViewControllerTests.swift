//
//  RoutePickerViewControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

private final class RouteSelectionRecorder: RoutePickerDelegate {
    private(set) var selected: [RouteID] = []

    func routePicker(_ picker: RoutePickerViewController, didSelectRoute route: Route) {
        selected.append(route.id)
    }
}

/// The UIKit route picker: its rows, search field and delegate.
/// `RoutePickerViewModelTests` covers how routes are loaded, deduplicated and filtered.
///
/// The controller starts its own load in `viewDidLoad` and keeps the view model
/// private. Each test reads that view model through `Mirror` only to await the
/// controller's load finishing, and drives everything else through the controller.
@Suite(.serialized, .timeLimit(.minutes(1)))
final class RoutePickerViewControllerTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Application

    /// - parameter stops: The stops-for-location payload to answer with, or `nil` for the Seattle fixture.
    private func buildApplication(withLocation: Bool = true, stops: Data? = nil) -> Application {
        let loader = MockDataLoader(testName: name)
        stubRegions(dataLoader: loader)
        stubAgenciesWithCoverage(dataLoader: loader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        loader.mock(data: stops ?? Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let locationService: LocationService
        if withLocation {
            let manager = MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
            locationService = LocationService(userDefaults: userDefaults, locationManager: manager)
            locationService.startUpdates()
        } else {
            locationService = LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock())
        }

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: loader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )
        return Application(config: config)
    }

    /// A stops-for-location payload with no stops.
    private func noStops() throws -> Data {
        var json = try JSONSerialization.jsonObject(with: Fixtures.loadData(file: "stops_for_location_seattle.json")) as! [String: Any]
        var data = json["data"] as! [String: Any]
        data["list"] = [[String: Any]]()
        json["data"] = data
        return try JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - Controller helpers

    /// Loads the view, which starts the controller's load, and waits for that load to finish.
    private func loadAndAwaitRoutes(_ controller: RoutePickerViewController) async throws {
        controller.loadViewIfNeeded()
        let viewModel = try #require(Mirror(reflecting: controller).descendant("viewModel") as? RoutePickerViewModel)
        for await finished in viewModel.$didFinishLoading.values where finished {
            break
        }
    }

    private func rows(_ controller: RoutePickerViewController) -> [OBAListRowView.SubtitleViewModel] {
        controller.items(for: OBAListView()).flatMap(\.contents).compactMap { $0.as(OBAListRowView.SubtitleViewModel.self) }
    }

    private func text(_ label: OBAListRowConfiguration.LabelText?) -> String? {
        guard case .string(let string) = label else { return nil }
        return string
    }

    private func emptyTitle(_ controller: RoutePickerViewController) -> String? {
        guard case .standard(let model) = controller.emptyData(for: OBAListView()) else { return nil }
        return model.title
    }

    private func search(_ controller: RoutePickerViewController, for query: String) throws {
        let searchController = try #require(controller.navigationItem.searchController)
        #expect(searchController.searchResultsUpdater === controller)
        searchController.searchBar.text = query
        controller.updateSearchResults(for: searchController)
    }

    // MARK: - Tests

    @Test func `Typing in the search field narrows the list to matching routes`() async throws {
        let recorder = RouteSelectionRecorder()
        let controller = RoutePickerViewController(application: buildApplication(), delegate: recorder)
        try await loadAndAwaitRoutes(controller)
        #expect(rows(controller).count == 34)

        try search(controller, for: "54")

        #expect(rows(controller).map { text($0.title) } == ["540", "541", "542"])
    }

    @Test func `A row shows the route's long name, or its agency when it has none`() async throws {
        let recorder = RouteSelectionRecorder()
        let controller = RoutePickerViewController(application: buildApplication(), delegate: recorder)
        try await loadAndAwaitRoutes(controller)

        try search(controller, for: "54")

        #expect(rows(controller).map { text($0.subtitle) } == [
            "Kirkland - University District", "Sound Transit", "Redmond - University District"
        ])
    }

    @Test func `Picking a route tells the delegate which one`() async throws {
        let recorder = RouteSelectionRecorder()
        let controller = RoutePickerViewController(application: buildApplication(), delegate: recorder)
        try await loadAndAwaitRoutes(controller)
        try search(controller, for: "54")

        let row = try #require(rows(controller).dropFirst().first)
        withExtendedLifetime(controller) {
            row.onSelectAction?(row)
        }

        #expect(recorder.selected == ["40_102640"])
    }

    @Test func `A failed load shows why instead of rows`() async throws {
        let recorder = RouteSelectionRecorder()
        let controller = RoutePickerViewController(application: buildApplication(withLocation: false), delegate: recorder)
        try await loadAndAwaitRoutes(controller)

        #expect(rows(controller).isEmpty)
        #expect(emptyTitle(controller) == RoutePickerViewModel.RoutePickerError.locationUnavailable.errorDescription)
    }

    @Test func `The list says it is loading until routes arrive, then says when none are nearby`() async throws {
        let recorder = RouteSelectionRecorder()
        let withRoutes = RoutePickerViewController(application: buildApplication(), delegate: recorder)
        withRoutes.loadViewIfNeeded()
        let loading = try #require(emptyTitle(withRoutes))

        try await loadAndAwaitRoutes(withRoutes)
        #expect(withRoutes.emptyData(for: OBAListView()) == nil)

        let withoutRoutes = RoutePickerViewController(application: buildApplication(stops: try noStops()), delegate: recorder)
        try await loadAndAwaitRoutes(withoutRoutes)
        #expect(rows(withoutRoutes).isEmpty)
        let noneNearby = try #require(emptyTitle(withoutRoutes))
        #expect(noneNearby != loading)
    }
}

// swiftlint:enable force_cast
