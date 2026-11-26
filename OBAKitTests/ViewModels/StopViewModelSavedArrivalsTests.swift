//
//  StopViewModelSavedArrivalsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The stop page offline: what was saved for a bookmarked stop stands in for
/// its arrivals when the device can't reach the server.
@Suite(.serialized)
final class StopViewModelSavedArrivalsTests: OBATestCase {

    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"
    private let arrivalsFixture = "arrivals-and-departures-for-stop-1_75414.json"
    private let scheduleFixture = "schedule-for-stop_1_75403.json"
    private let stopID = "1_75414"

    private var directory: URL!
    private var store: SavedArrivalsStore!
    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()
        directory = FileManager.default.temporaryDirectory.appending(path: "StopViewModelSavedArrivalsTests-\(UUID().uuidString)")
        store = SavedArrivalsStore(directory: directory)
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    private func mockArrivalsError(_ dataLoader: MockDataLoader, _ error: Error) {
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: error) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        })
    }

    private func mockArrivals(_ dataLoader: MockDataLoader, body: Data) {
        dataLoader.mock(data: body) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
    }

    private func mockArrivalsStatus(_ dataLoader: MockDataLoader, statusCode: Int) {
        dataLoader.mock(data: Data("{}".utf8), statusCode: statusCode) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
    }

    /// Everything a `StopViewModel` refresh touches besides the arrivals call.
    private func mockSupportingCalls(_ dataLoader: MockDataLoader) {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        let emptySurveys = Data(#"{"surveys":[],"region":{"id":1,"name":"Puget Sound"}}"#.utf8)
        dataLoader.mock(data: emptySurveys) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }
    }

    @MainActor
    private func makeViewModel(dataLoader: MockDataLoader, savedArrivals: SavedArrivalsStore?) -> StopViewModel {
        mockSupportingCalls(dataLoader)
        let locationService = LocationService(
            userDefaults: userDefaults,
            locationManager: MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        )
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
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name,
            savedArrivals: savedArrivals,
            retryPolicy: .disabled
        )
        return StopViewModel(application: Application(config: config), stopID: stopID)
    }

    /// The arrivals fixture with its one departure copied to leave at each of
    /// `minutesFromNow`.
    private func arrivalsBody(departingInMinutes minutesFromNow: [Double]) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: Fixtures.loadData(file: arrivalsFixture)) as? [String: Any])
        var data = try #require(root["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        let template = try #require((entry["arrivalsAndDepartures"] as? [[String: Any]])?.first)
        var references = try #require(data["references"] as? [String: Any])
        let tripTemplate = try #require((references["trips"] as? [[String: Any]])?.first)

        let nowMS = Date().timeIntervalSince1970 * 1000
        // Each copy gets its own stop sequence, or decoding keeps only one, and
        // its own trip, or the page's terminal dedup merges them.
        let baseSequence = template["stopSequence"] as? Int ?? 0
        let tripIDs = minutesFromNow.indices.map { "copy_trip_\($0)" }
        references["trips"] = [tripTemplate] + tripIDs.map { id in
            var trip = tripTemplate
            trip["id"] = id
            return trip
        }
        data["references"] = references
        entry["arrivalsAndDepartures"] = minutesFromNow.enumerated().map { index, minutes in
            var departure = template
            departure["stopSequence"] = baseSequence + index
            departure["tripId"] = tripIDs[index]
            let time = Int64(nowMS + minutes * 60_000)
            for key in ["predictedArrivalTime", "predictedDepartureTime", "scheduledArrivalTime", "scheduledDepartureTime"] {
                departure[key] = time
            }
            return departure
        }
        data["entry"] = entry
        root["data"] = data
        root["currentTime"] = Int64(nowMS)
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// The timetable fixture with its first route's first direction running at
    /// each of `minutesFromNow`. Every other trip in it is from 2025.
    private func scheduleBody(departingInMinutes minutesFromNow: [Double]) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: Fixtures.loadData(file: scheduleFixture)) as? [String: Any])
        var data = try #require(root["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        var routes = try #require(entry["stopRouteSchedules"] as? [[String: Any]])
        var directions = try #require(routes[0]["stopRouteDirectionSchedules"] as? [[String: Any]])
        let template = try #require((directions[0]["scheduleStopTimes"] as? [[String: Any]])?.first)

        let nowMS = Date().timeIntervalSince1970 * 1000
        directions[0]["scheduleStopTimes"] = minutesFromNow.enumerated().map { index, minutes in
            var stopTime = template
            stopTime["tripId"] = "timetable_trip_\(index)"
            stopTime["arrivalTime"] = Int64(nowMS + minutes * 60_000)
            stopTime["departureTime"] = Int64(nowMS + minutes * 60_000)
            return stopTime
        }
        routes[0]["stopRouteDirectionSchedules"] = directions
        entry["stopRouteSchedules"] = routes
        data["entry"] = entry
        root["data"] = data
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func save(arrivals: Data? = nil, schedule: Data? = nil, savedAt: Date = Date()) {
        if let arrivals {
            store.save(arrivals, stopID: stopID, regionID: pugetSoundRegionIdentifier, savedAt: savedAt)
        }
        if let schedule {
            store.save(schedule, kind: .schedule, stopID: stopID, regionID: pugetSoundRegionIdentifier, savedAt: savedAt)
        }
    }

    // MARK: - Tests

    @Test @MainActor
    func `Offline the page shows the saved departures that haven't left`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [-10, 6, 20]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)

        await viewModel.refresh()

        let saved = try #require(viewModel.savedArrivals)
        #expect(saved.arrivals.count == 2)
        #expect(viewModel.stopArrivals == nil)
        #expect(viewModel.operationError != nil)
        #expect(viewModel.statusText.hasPrefix("Offline, saved"))

        let content = StopPageContent(viewModel: viewModel)
        #expect(content.hasLoadedArrivals)
        #expect(!content.showsLoadingState)
        #expect(content.departures.count == 2)
        #expect(content.showsStaleArrivalsNotice)
    }

    @Test @MainActor
    func `A timeout falls back to the saved departures too`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [8]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.timedOut))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)

        await viewModel.refresh()

        #expect(viewModel.savedArrivals?.arrivals.count == 1)
    }

    @Test @MainActor
    func `The saved timetable is shown after the saved departures`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [5]), schedule: try scheduleBody(departingInMinutes: [-3, 70, 90]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)

        await viewModel.refresh()

        let content = StopPageContent(viewModel: viewModel)
        #expect(content.departures.count == 1)
        #expect(content.scheduledDepartures.count == 2)
        #expect(content.scheduledDepartures.allSatisfy { $0.minutes >= 0 })
    }

    @Test @MainActor
    func `With only the timetable left the label says scheduled times`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [-15]), schedule: try scheduleBody(departingInMinutes: [12]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)

        await viewModel.refresh()

        #expect(viewModel.statusText == "Offline, scheduled times")
        #expect(StopPageContent(viewModel: viewModel).scheduledDepartures.count == 1)
    }

    @Test @MainActor
    func `The real time only filter hides the timetable`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [5]), schedule: try scheduleBody(departingInMinutes: [70]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)
        viewModel.updateArrivalDepartureFilter(.estimatedOnly)

        await viewModel.refresh()

        #expect(StopPageContent(viewModel: viewModel).scheduledDepartures.isEmpty)
    }

    /// Saved rows all render as schedule data, so the "Scheduled only" filter
    /// must not remove the ones that were saved with a prediction: the
    /// timetable already skips their trips, and offline the rider would see
    /// neither departure nor timetable entry.
    @Test @MainActor
    func `The scheduled only filter keeps the saved departures`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [6, 20]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)
        viewModel.updateArrivalDepartureFilter(.scheduledOnly)

        await viewModel.refresh()

        let saved = try #require(viewModel.savedArrivals)
        let allPredicted = saved.arrivals.allSatisfy(\.predicted)
        #expect(allPredicted, "fixture premise: the saved departures were predicted")
        #expect(StopPageContent(viewModel: viewModel).departures.count == 2)
    }

    /// A stop the server said is gone stays gone: saved departures for it
    /// must not come back once the phone drops offline.
    @Test @MainActor
    func `A missing stop doesn't come back from the saved departures`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [5]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsStatus(dataLoader, statusCode: 404)
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)

        await viewModel.refresh()
        #expect(viewModel.stopIsMissing)
        #expect(viewModel.savedArrivals == nil)

        dataLoader.replaceMappedResponses { loader in
            mockSupportingCalls(loader)
            mockArrivalsError(loader, URLError(.notConnectedToInternet))
        }
        await viewModel.refresh()

        #expect(viewModel.stopIsMissing)
        #expect(viewModel.savedArrivals == nil)
    }

    @Test @MainActor
    func `Offline with nothing saved still shows the error`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)

        await viewModel.refresh()

        #expect(viewModel.savedArrivals == nil)
        let content = StopPageContent(viewModel: viewModel)
        #expect(!content.hasLoadedArrivals)
        #expect(!content.showsLoadingState)
        #expect(viewModel.operationErrorMessage != nil)
    }

    /// A server error isn't about the connection, so saved data would hide it.
    @Test @MainActor
    func `A server error doesn't fall back`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [5]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsStatus(dataLoader, statusCode: 500)
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)

        await viewModel.refresh()

        #expect(viewModel.savedArrivals == nil)
        #expect(viewModel.operationError != nil)
    }

    @Test @MainActor
    func `Without a store the page shows the error as before`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [5]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: nil)

        await viewModel.refresh()

        #expect(viewModel.savedArrivals == nil)
    }

    @Test @MainActor
    func `Getting back online replaces the saved departures`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [5]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)
        await viewModel.refresh()
        #expect(viewModel.savedArrivals != nil)

        let live = try arrivalsBody(departingInMinutes: [3, 9, 14])
        dataLoader.replaceMappedResponses { loader in
            mockSupportingCalls(loader)
            mockArrivals(loader, body: live)
        }
        await viewModel.refresh()

        #expect(viewModel.savedArrivals == nil)
        #expect(viewModel.operationError == nil)
        #expect(viewModel.stopArrivals?.arrivalsAndDepartures.count == 3)
        #expect(!viewModel.statusText.hasPrefix("Offline"))
    }

    /// Departures this page already fetched are at least as fresh as saved
    /// ones, so they stay, under the stale notice.
    @Test @MainActor
    func `Going offline after a live load keeps the live departures`() async throws {
        save(arrivals: try arrivalsBody(departingInMinutes: [5]))
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, body: try arrivalsBody(departingInMinutes: [3, 9, 14]))
        let viewModel = makeViewModel(dataLoader: dataLoader, savedArrivals: store)
        await viewModel.refresh()

        dataLoader.replaceMappedResponses { loader in
            mockSupportingCalls(loader)
            mockArrivalsError(loader, URLError(.notConnectedToInternet))
        }
        await viewModel.refresh()

        #expect(viewModel.savedArrivals == nil)
        #expect(viewModel.stopArrivals?.arrivalsAndDepartures.count == 3)
        #expect(StopPageContent(viewModel: viewModel).showsStaleArrivalsNotice)
    }
}
