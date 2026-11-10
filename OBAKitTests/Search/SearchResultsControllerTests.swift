//
//  SearchResultsControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The UIKit search results list: which rows it builds, and where each one goes
/// when tapped. `SearchViewModelTests` covers the view model underneath it.
@MainActor
@Suite(.serialized)
final class SearchResultsControllerTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private final class RecordingModalDelegate: NSObject, ModalDelegate {
        var dismissed: [UIViewController] = []
        var onDismiss: (() -> Void)?

        func dismissModalController(_ controller: UIViewController) {
            dismissed.append(controller)
            onDismiss?()
        }
    }

    // MARK: - Helpers

    private func application(_ loader: MockDataLoader) -> Application {
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        return buildApplication(queue: queue, dataLoader: loader)
    }

    /// No location authorization and no fixed region, so `apiService` is nil.
    private func applicationWithoutAPIService() throws -> Application {
        let loader = MockDataLoader(testName: name)
        stubRegions(dataLoader: loader)
        Fixtures.stubAllAgencyAlerts(dataLoader: loader)
        let locationService = LocationService(userDefaults: userDefaults, locationManager: LocationManagerMock())
        let config = AppConfig(regionsBaseURL: regionsURL, apiKey: apiKey, appVersion: appVersion, userDefaults: userDefaults, analytics: AnalyticsMock(), queue: queue, locationService: locationService, bundledRegionsFilePath: bundledRegionsPath, regionsAPIPath: regionsAPIPath, dataLoader: loader)
        let application = Application(config: config)
        try #require(application.apiService == nil)
        return application
    }

    private func controller(results: [Any], application: Application, delegate: ModalDelegate?) -> SearchResultsController {
        let response = SearchResponse(request: SearchRequest(query: "44", type: .route), results: results, boundingRegion: nil, error: nil)
        let controller = SearchResultsController(searchResponse: response, application: application, delegate: delegate)
        controller.loadViewIfNeeded()
        return controller
    }

    private func rows(_ controller: SearchResultsController) -> [AnyOBAListViewItem] {
        controller.items(for: OBAListView()).flatMap(\.contents)
    }

    private func string(_ text: OBAListRowConfiguration.LabelText?) -> String? {
        if case .string(let value) = text { return value }
        return nil
    }

    /// The row's title and subtitle, whichever row style it uses.
    private func texts(_ row: AnyOBAListViewItem) -> (title: String?, subtitle: String?) {
        if let row = row.as(OBAListRowView.SubtitleViewModel.self) {
            return (string(row.title), string(row.subtitle))
        }
        if let row = row.as(OBAListRowView.DefaultViewModel.self) {
            return (string(row.title), nil)
        }
        return (nil, nil)
    }

    private func place(named name: String) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3422)))
        item.name = name
        return item
    }

    private func vehicle(id: String?) throws -> AgencyVehicle {
        var dictionary: [String: Any] = ["id": "1", "name": "King County Metro"]
        dictionary["vehicle_id"] = id
        return try Fixtures.dictionaryToModel(type: AgencyVehicle.self, dictionary: dictionary)
    }

    private func stubStopsForRoute(_ loader: MockDataLoader) {
        loader.mock(data: Fixtures.loadData(file: "stops_for_route_1_44.json")) { request in
            request.url?.path.contains("/api/where/stops-for-route/") ?? false
        }
    }

    // MARK: - Rows

    @Test func `Each result becomes one row with its name, and its agency where it has one`() throws {
        let application = application(MockDataLoader(testName: name))
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let results: [Any] = [place(named: "Pike Place Market"), try Fixtures.createRoute(id: "1_44"), stop, try vehicle(id: "1_4351")]

        let rows = rows(controller(results: results, application: application, delegate: nil))

        #expect(rows.count == 4)
        #expect(texts(rows[0]) == ("Pike Place Market", nil))
        #expect(texts(rows[1]) == ("1", "Test Agency"))
        #expect(texts(rows[2]) == (stop.name, nil))
        #expect(texts(rows[3]) == ("1_4351", "King County Metro"))
    }

    @Test func `A vehicle with no ID gets no row`() throws {
        let application = application(MockDataLoader(testName: name))
        let results: [Any] = [try vehicle(id: nil), try vehicle(id: "1_4351")]

        let rows = rows(controller(results: results, application: application, delegate: nil))

        #expect(rows.count == 1)
        #expect(texts(rows[0]).title == "1_4351")
    }

    /// A vehicle row fetches the vehicle when tapped, so it can't work without a server.
    @Test func `Vehicles get no row when there is no transit data service`() throws {
        let application = try applicationWithoutAPIService()
        let results: [Any] = [try vehicle(id: "1_4351"), place(named: "Pike Place Market")]

        let rows = rows(controller(results: results, application: application, delegate: nil))

        #expect(rows.count == 1)
        #expect(texts(rows[0]).title == "Pike Place Market")
    }

    // MARK: - Taps

    @Test func `Tapping a stop shows just that stop on the map and closes the list`() throws {
        let application = application(MockDataLoader(testName: name))
        let stops = try Fixtures.loadSomeStops()
        let delegate = RecordingModalDelegate()
        let controller = controller(results: [stops[0], stops[1]], application: application, delegate: delegate)

        let row = rows(controller)[1]
        row.onSelectAction?(row)

        let shown = try #require(application.mapRegionManager.searchResponse)
        #expect(shown.results.count == 1)
        #expect((shown.results.first as? Stop) === stops[1])
        #expect(delegate.dismissed == [controller])
    }

    @Test func `Tapping a route shows just that route on the map and closes the list`() throws {
        let loader = MockDataLoader(testName: name)
        // The map loads the route's stops once it has the route.
        stubStopsForRoute(loader)
        let application = application(loader)
        let first = try Fixtures.createRoute(id: "1_44")
        let second = try Fixtures.createRoute(id: "40_100236")
        let delegate = RecordingModalDelegate()
        let controller = controller(results: [first, second], application: application, delegate: delegate)

        let row = rows(controller)[1]
        row.onSelectAction?(row)

        let shown = try #require(application.mapRegionManager.searchResponse)
        #expect(shown.results.count == 1)
        #expect((shown.results.first as? Route)?.id == "40_100236")
        #expect(delegate.dismissed == [controller])
    }

    @Test func `Tapping a place shows just that place on the map and closes the list`() throws {
        let application = application(MockDataLoader(testName: name))
        let museum = place(named: "Seattle Art Museum")
        let delegate = RecordingModalDelegate()
        let controller = controller(results: [place(named: "Pike Place Market"), museum], application: application, delegate: delegate)

        let row = rows(controller)[1]
        row.onSelectAction?(row)

        // Read before the next run loop pass: the map clears a place result then,
        // so panning goes back to loading stops.
        let shown = try #require(application.mapRegionManager.searchResponse)
        #expect(shown.results.count == 1)
        #expect((shown.results.first as? MKMapItem) === museum)
        #expect(delegate.dismissed == [controller])
    }

    @Test(.timeLimit(.minutes(1)))
    func `Tapping a vehicle fetches it, shows it on the map and closes the list`() async throws {
        let loader = MockDataLoader(testName: name)
        loader.mock(data: Fixtures.loadData(file: "api_where_vehicle_1_4351.json")) { request in
            request.url?.path.hasSuffix("/api/where/vehicle/1_4351.json") ?? false
        }
        let application = application(loader)
        let delegate = RecordingModalDelegate()
        let controller = controller(results: [try vehicle(id: "1_4351")], application: application, delegate: delegate)
        let row = try #require(rows(controller).first)

        // The fetch runs in its own task; the list closes once the vehicle is on the map.
        await withCheckedContinuation { continuation in
            delegate.onDismiss = { continuation.resume() }
            row.onSelectAction?(row)
        }

        let shown = try #require(application.mapRegionManager.searchResponse)
        #expect(shown.results.count == 1)
        #expect((shown.results.first as? VehicleStatus)?.vehicleID == "1_4351")
        #expect(delegate.dismissed == [controller])
    }
}
