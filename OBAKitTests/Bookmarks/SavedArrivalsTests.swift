//
//  SavedArrivalsTests.swift
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

/// Saved arrivals: a bookmarked stop's last arrivals response, kept on disk and
/// shown, marked as saved, when the device can't reach the server.
@Suite(.serialized)
final class SavedArrivalsTests: OBATestCase {

    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"
    private let fixtureFile = "arrivals-and-departures-for-stop-1_75414.json"
    private let stopID = "1_75414"

    private var directory: URL!
    private var store: SavedArrivalsStore!

    override init() async throws {
        try await super.init()
        directory = FileManager.default.temporaryDirectory.appending(path: "SavedArrivalsTests-\(UUID().uuidString)")
        store = SavedArrivalsStore(directory: directory)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    private func isArrivalsRequest(_ request: URLRequest) -> Bool {
        request.url?.path.contains(arrivalsPath) ?? false
    }

    private func mockArrivals(_ dataLoader: MockDataLoader) {
        dataLoader.mock(data: Fixtures.loadData(file: fixtureFile)) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
    }

    private let schedulePath = "/api/where/schedule-for-stop"
    private let scheduleFixture = "schedule-for-stop_1_75403.json"

    /// A good fetch with a store also saves the day's timetable, so every
    /// test where a fetch succeeds needs this too.
    private func mockSchedule(_ dataLoader: MockDataLoader, body: Data? = nil, log: (@Sendable (String) -> Void)? = nil) {
        dataLoader.mock(data: body ?? Fixtures.loadData(file: scheduleFixture)) { [schedulePath] request in
            guard let path = request.url?.path, path.contains(schedulePath) else { return false }
            log?(path)
            return true
        }
    }

    /// The timetable fixture, with its first route renamed to `routeID` and
    /// `headsign` and running at each of `minutesFromNow`, and the second
    /// route's first trip `otherRouteMinutes` from now. Every other trip in the
    /// fixture is from 2025, so has left.
    private func scheduleBody(routeID: String, headsign: String, departingInMinutes minutesFromNow: [Double], otherRouteMinutes: Double = 3, tripIDs: [String]? = nil, daysEarlier: Double = 0) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: Fixtures.loadData(file: scheduleFixture)) as? [String: Any])
        var data = try #require(root["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        var routes = try #require(entry["stopRouteSchedules"] as? [[String: Any]])
        let nowMS = Date().timeIntervalSince1970 * 1000

        func retimed(_ stopTime: [String: Any], minutes: Double) -> [String: Any] {
            var stopTime = stopTime
            stopTime["arrivalTime"] = Int64(nowMS + minutes * 60_000)
            stopTime["departureTime"] = Int64(nowMS + minutes * 60_000)
            return stopTime
        }

        var first = routes[0]
        var firstDirections = try #require(first["stopRouteDirectionSchedules"] as? [[String: Any]])
        let template = try #require((firstDirections[0]["scheduleStopTimes"] as? [[String: Any]])?.first)
        first["routeId"] = routeID
        firstDirections[0]["tripHeadsign"] = headsign
        firstDirections[0]["scheduleStopTimes"] = minutesFromNow.enumerated().map { index, minutes in
            var stopTime = retimed(template, minutes: minutes)
            stopTime["tripId"] = tripIDs?[index] ?? "trip_\(index)"
            return stopTime
        }
        first["stopRouteDirectionSchedules"] = firstDirections
        routes[0] = first

        var second = routes[1]
        var secondDirections = try #require(second["stopRouteDirectionSchedules"] as? [[String: Any]])
        var secondTimes = try #require(secondDirections[0]["scheduleStopTimes"] as? [[String: Any]])
        secondTimes[0] = retimed(secondTimes[0], minutes: otherRouteMinutes)
        secondDirections[0]["scheduleStopTimes"] = secondTimes
        second["stopRouteDirectionSchedules"] = secondDirections
        routes[1] = second

        entry["stopRouteSchedules"] = routes
        if daysEarlier != 0, let date = entry["date"] as? Double {
            entry["date"] = date - daysEarlier * 86_400_000
        }
        data["entry"] = entry
        root["data"] = data
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func mockArrivalsError(_ dataLoader: MockDataLoader, _ error: Error) {
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: error) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        })
    }

    private func mockArrivalsStatus(_ dataLoader: MockDataLoader, statusCode: Int) {
        dataLoader.mock(data: Data("{}".utf8), statusCode: statusCode) { [arrivalsPath] request in
            request.url?.path.contains(arrivalsPath) ?? false
        }
    }

    /// The fixture's response with its one departure copied to leave at each of
    /// `minutesFromNow`. The fixture itself is from 2018, so as saved it holds
    /// only departures that have left.
    private func savedBody(departingInMinutes minutesFromNow: [Double]) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: Fixtures.loadData(file: fixtureFile)) as? [String: Any])
        var data = try #require(root["data"] as? [String: Any])
        var entry = try #require(data["entry"] as? [String: Any])
        let template = try #require((entry["arrivalsAndDepartures"] as? [[String: Any]])?.first)

        let nowMS = Date().timeIntervalSince1970 * 1000
        // Each copy gets its own stop sequence: copies that shared one would be
        // the same visit, and decoding keeps only one of those.
        let baseSequence = template["stopSequence"] as? Int ?? 0
        entry["arrivalsAndDepartures"] = minutesFromNow.enumerated().map { index, minutes in
            var departure = template
            departure["stopSequence"] = baseSequence + index
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

    /// The single result the loader streams for `stopID`.
    private func loadOnce(_ loader: BookmarkArrivalsLoader, service: RESTAPIService) async -> Result<[ArrivalDeparture], Error>? {
        var delivered: Result<[ArrivalDeparture], Error>?
        for await (_, result) in loader.arrivals(for: [BookmarkArrivalsRequest(stopID: stopID)], using: service) {
            delivered = result
        }
        return delivered
    }

    // MARK: - Store

    @Test func `A saved body loads back with its save date`() throws {
        let body = Data("{\"hello\":1}".utf8)
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.save(body, stopID: stopID, regionID: 1, savedAt: savedAt)

        let loaded = try #require(store.load(stopID: stopID, regionID: 1))
        #expect(loaded.body == body)
        #expect(abs(loaded.savedAt.timeIntervalSince(savedAt)) < 1)
    }

    @Test func `A later save replaces the earlier one`() throws {
        store.save(Data("old".utf8), stopID: stopID, regionID: 1)
        store.save(Data("new".utf8), stopID: stopID, regionID: 1)

        #expect(try #require(store.load(stopID: stopID, regionID: 1)).body == Data("new".utf8))
    }

    /// A body only decodes against its own region's service.
    @Test func `Saved bodies are kept apart by region`() {
        store.save(Data("one".utf8), stopID: stopID, regionID: 1)

        #expect(store.load(stopID: stopID, regionID: 2) == nil)
    }

    @Test func `Nothing saved loads nil`() {
        #expect(store.load(stopID: stopID, regionID: 1) == nil)
    }

    @Test func `A stop ID with a slash stays inside the store's folder`() throws {
        let oddStopID = "agency/../stop 1"
        store.save(Data("x".utf8), stopID: oddStopID, regionID: 1)

        #expect(try #require(store.load(stopID: oddStopID, regionID: 1)).body == Data("x".utf8))
        let url = store.fileURL(stopID: oddStopID, regionID: 1)
        #expect(url.deletingLastPathComponent().lastPathComponent == "1")
        #expect(url.path.hasPrefix(directory.path))
    }

    // MARK: - BookmarkArrivalsLoader

    @Test func `A successful fetch saves the response`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader)
        mockSchedule(dataLoader)
        let service = buildRESTService(dataLoader: dataLoader)

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: service)

        #expect((try? result?.get())?.isEmpty == false)
        let saved = try #require(store.load(stopID: stopID, regionID: pugetSoundRegionIdentifier))
        #expect(saved.body == Fixtures.loadData(file: fixtureFile))
    }

    @Test func `Without a store nothing is saved`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader)

        _ = await loadOnce(BookmarkArrivalsLoader(), service: buildRESTService(dataLoader: dataLoader))

        #expect(store.load(stopID: stopID, regionID: pugetSoundRegionIdentifier) == nil)
    }

    @Test func `Offline with saved arrivals fails with them as a fallback`() async throws {
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(try savedBody(departingInMinutes: [5, 15]), stopID: stopID, regionID: pugetSoundRegionIdentifier, savedAt: savedAt)

        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure, got \(String(describing: result))")
            return
        }
        let fallback = try #require(error as? SavedArrivalsFallback)
        #expect(fallback.arrivals.count == 2)
        #expect(fallback.arrivals.allSatisfy { $0.temporalState == .future })
        #expect(abs(fallback.savedAt.timeIntervalSince(savedAt)) < 1)
        #expect(ErrorClassifier.category(for: fallback.underlyingError) == .offline)
    }

    /// A live fetch never returns a departure that has left; saved ones age.
    @Test func `Saved departures that have left are dropped`() async throws {
        store.save(try savedBody(departingInMinutes: [-10, -2, 0.5, 12]), stopID: stopID, regionID: pugetSoundRegionIdentifier)
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure, got \(String(describing: result))")
            return
        }
        let fallback = try #require(error as? SavedArrivalsFallback)
        #expect(fallback.arrivals.count == 2)
        #expect(fallback.arrivals.allSatisfy { $0.temporalState != .past })
    }

    /// A request that times out on a weak signal is as offline as no signal.
    @Test func `A timeout with saved arrivals falls back too`() async throws {
        store.save(Fixtures.loadData(file: fixtureFile), stopID: stopID, regionID: pugetSoundRegionIdentifier)
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.timedOut))

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure, got \(String(describing: result))")
            return
        }
        #expect(error is SavedArrivalsFallback)
    }

    @Test func `Offline with nothing saved fails with the original error`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure, got \(String(describing: result))")
            return
        }
        #expect(!(error is SavedArrivalsFallback))
        #expect(ErrorClassifier.category(for: error) == .offline)
    }

    /// The server answered, so its error is the news: saved data would hide it.
    @Test func `A server error does not fall back to saved arrivals`() async {
        store.save(Fixtures.loadData(file: fixtureFile), stopID: stopID, regionID: pugetSoundRegionIdentifier)
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsStatus(dataLoader, statusCode: 500)

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure, got \(String(describing: result))")
            return
        }
        #expect(!(error is SavedArrivalsFallback))
    }

    @Test func `A saved body that no longer decodes is ignored`() async {
        store.save(Data("not json".utf8), stopID: stopID, regionID: pugetSoundRegionIdentifier)
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure, got \(String(describing: result))")
            return
        }
        #expect(!(error is SavedArrivalsFallback))
    }

    /// A loader with no store, like the widget's, never sees a fallback.
    @Test func `A loader without a store does not fall back`() async {
        store.save(Fixtures.loadData(file: fixtureFile), stopID: stopID, regionID: pugetSoundRegionIdentifier)
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let result = await loadOnce(BookmarkArrivalsLoader(), service: buildRESTService(dataLoader: dataLoader))

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure, got \(String(describing: result))")
            return
        }
        #expect(!(error is SavedArrivalsFallback))
    }

    // MARK: - Timetable

    /// Sendable request counter for the timetable mock, which runs off the main actor.
    private nonisolated final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    @Test func `A timetable flattens to departures, soonest first, with route colors`() throws {
        let service = buildRESTService()
        let schedule = try service.decodeKeptBody(ScheduleForStop.self, from: Fixtures.loadData(file: scheduleFixture)).entry

        let departures = schedule.scheduledDepartures

        #expect(departures.count == 67 + 65 + 61)
        #expect(departures.map(\.date) == departures.map(\.date).sorted())
        #expect(Set(departures.map(\.routeID)) == ["1_100225", "1_100259", "1_100214"])
        #expect(departures.allSatisfy { $0.route?.color != nil })
        #expect(departures.first { $0.routeID == "1_100225" }?.tripHeadsign == "Loyal Heights Greenwood")
    }

    @Test func `A good fetch saves today's timetable, once a day`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let requests = Counter()
        mockArrivals(dataLoader)
        mockSchedule(dataLoader) { _ in requests.increment() }
        let service = buildRESTService(dataLoader: dataLoader)
        let loader = BookmarkArrivalsLoader(savedArrivals: store)

        _ = await loadOnce(loader, service: service)
        _ = await loadOnce(loader, service: service)

        #expect(requests.count == 1)
        let saved = try #require(store.load(kind: .schedule, stopID: stopID, regionID: pugetSoundRegionIdentifier))
        #expect(saved.body == Fixtures.loadData(file: scheduleFixture))
        #expect(Calendar.current.isDateInToday(saved.savedAt))
    }

    @Test func `A timetable saved yesterday is fetched again`() async throws {
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        store.save(Data("old".utf8), kind: .schedule, stopID: stopID, regionID: pugetSoundRegionIdentifier, savedAt: yesterday)
        let dataLoader = MockDataLoader(testName: name)
        let requests = Counter()
        mockArrivals(dataLoader)
        mockSchedule(dataLoader) { _ in requests.increment() }

        _ = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        #expect(requests.count == 1)
        let saved = try #require(store.load(kind: .schedule, stopID: stopID, regionID: pugetSoundRegionIdentifier))
        #expect(Calendar.current.isDateInToday(saved.savedAt))
    }

    /// The departures are what the rider came for; the timetable is extra.
    @Test func `A failed timetable fetch leaves the arrivals alone`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader)
        dataLoader.mock(data: Data("{}".utf8), statusCode: 500) { [schedulePath] request in
            request.url?.path.contains(schedulePath) ?? false
        }

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        #expect((try? result?.get())?.isEmpty == false)
        #expect(store.load(kind: .schedule, stopID: stopID, regionID: pugetSoundRegionIdentifier) == nil)
    }

    @Test func `Offline with only a timetable saved falls back to it`() async throws {
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let body = try scheduleBody(routeID: "1_A", headsign: "Downtown", departingInMinutes: [-3, 5, 20], otherRouteMinutes: 3)
        store.save(body, kind: .schedule, stopID: stopID, regionID: pugetSoundRegionIdentifier, savedAt: savedAt)
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure, got \(String(describing: result))")
            return
        }
        let fallback = try #require(error as? SavedArrivalsFallback)
        #expect(fallback.arrivals.isEmpty)
        #expect(abs(fallback.savedAt.timeIntervalSince(savedAt)) < 1)
        // The trip that left 3 minutes ago is gone; the other route's stays.
        #expect(fallback.scheduledDepartures.count == 3)
        #expect(fallback.scheduledDepartures.filter { $0.routeID == "1_A" }.count == 2)
        #expect(fallback.scheduledDepartures.allSatisfy { $0.minutes >= 0 })
    }

    /// A saved trip that has left is dropped from the departures, but its
    /// prediction still counts: if it left ahead of its timetable time, that
    /// time must not bring it back.
    @Test func `The timetable skips saved trips that have already left`() async throws {
        let leftTripID = "1_39683959"
        store.save(try savedBody(departingInMinutes: [-1]), stopID: stopID, regionID: pugetSoundRegionIdentifier)
        let schedule = try scheduleBody(routeID: "1_A", headsign: "Downtown", departingInMinutes: [2, 20], tripIDs: [leftTripID, "later"])
        store.save(schedule, kind: .schedule, stopID: stopID, regionID: pugetSoundRegionIdentifier)
        let dataLoader = MockDataLoader(testName: name)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let result = await loadOnce(BookmarkArrivalsLoader(savedArrivals: store), service: buildRESTService(dataLoader: dataLoader))

        guard case .failure(let error) = result else {
            Issue.record("Expected a failure, got \(String(describing: result))")
            return
        }
        let fallback = try #require(error as? SavedArrivalsFallback)
        #expect(fallback.arrivals.isEmpty)
        #expect(fallback.scheduledDepartures.contains { $0.tripID == leftTripID } == false)
        #expect(fallback.scheduledDepartures.contains { $0.tripID == "later" })
    }

    // MARK: - BookmarkDataLoader

    @MainActor
    private final class Delegate: NSObject, BookmarkDataDelegate {
        func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {}
    }

    @MainActor
    private func makeTripBookmark(application: Application) throws -> Bookmark {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures
        let arrivalDeparture = try #require(arrivals.first)
        let bookmark = Bookmark(name: "Saved", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture)
        application.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    /// Offline, the card shows the saved departures with their save date;
    /// back online, live ones replace them and the date clears.
    @Test @MainActor
    func `The data loader shows saved departures offline and live ones after`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let bookmark = try makeTripBookmark(application: application)
        let key = try #require(TripBookmarkKey(bookmark: bookmark))
        let regionID = try #require(application.apiService?.regionIdentifier)

        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(try savedBody(departingInMinutes: [8]), stopID: bookmark.stopID, regionID: regionID, savedAt: savedAt)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let delegate = Delegate()
        let loader = BookmarkDataLoader(
            application: application,
            delegate: delegate,
            bookmarkProvider: { [bookmark] },
            autoRefreshes: false,
            savedArrivals: store
        )

        await loader.loadDataAndWait()

        let offlineDate = try #require(loader.savedArrivalsDate(forStopID: bookmark.stopID))
        #expect(abs(offlineDate.timeIntervalSince(savedAt)) < 1)
        #expect(loader.dataForKey(key).isEmpty == false)
        #expect(loader.lastBatchHadError)

        dataLoader.replaceMappedResponses {
            self.mockArrivals($0)
            self.mockSchedule($0)
        }
        await loader.loadDataAndWait()

        #expect(loader.savedArrivalsDate(forStopID: bookmark.stopID) == nil)
        #expect(loader.hasFetchedData(forStopID: bookmark.stopID))
        #expect(loader.lastBatchHadError == false)
    }

    /// Once the saved real-time departures have all left, the bookmark's own
    /// route and headsign come from the timetable; other routes don't.
    @Test @MainActor
    func `Offline, a bookmark whose saved departures have left gets its timetable`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let bookmark = try makeTripBookmark(application: application)
        let key = try #require(TripBookmarkKey(bookmark: bookmark))
        let regionID = try #require(application.apiService?.regionIdentifier)

        store.save(try savedBody(departingInMinutes: [-10]), stopID: bookmark.stopID, regionID: regionID)
        let schedule = try scheduleBody(routeID: key.routeID, headsign: key.tripHeadsign, departingInMinutes: [6, 21, 36], otherRouteMinutes: 3)
        store.save(schedule, kind: .schedule, stopID: bookmark.stopID, regionID: regionID)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let loader = BookmarkDataLoader(application: application, delegate: Delegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false, savedArrivals: store)
        await loader.loadDataAndWait()

        #expect(loader.dataForKey(key).isEmpty)
        #expect(loader.savedArrivalsDate(forStopID: bookmark.stopID) != nil)
        let timetable = loader.scheduledDepartures(for: key)
        #expect(timetable.count == 3)
        #expect(timetable.allSatisfy { $0.routeID == key.routeID })

        dataLoader.replaceMappedResponses {
            self.mockArrivals($0)
            self.mockSchedule($0)
        }
        await loader.loadDataAndWait()

        #expect(loader.scheduledDepartures(for: key).isEmpty)
    }

    @MainActor
    private func makeDestinationBookmark(application: Application) throws -> Bookmark {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures
        let arrivalDeparture = try #require(arrivals.first)
        let destinationStop = try #require(try Fixtures.loadSomeStops().first { $0.id != arrivalDeparture.stopID })
        let bookmark = Bookmark(name: "Commute", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture, destinationStop: destinationStop)
        application.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    /// Two trips share the route and headsign, but only one reaches the
    /// destination; a third reaches it before the origin. Offline, the
    /// destination bookmark's timetable keeps only the first.
    @Test @MainActor
    func `Offline, a destination bookmark's timetable leaves out short turns`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let bookmark = try makeDestinationBookmark(application: application)
        let key = try #require(TripBookmarkKey(bookmark: bookmark))
        let destinationStopID = try #require(bookmark.destinationStopID)
        let regionID = try #require(application.apiService?.regionIdentifier)

        store.save(try savedBody(departingInMinutes: [-10]), stopID: bookmark.stopID, regionID: regionID)
        let origin = try scheduleBody(routeID: key.routeID, headsign: key.tripHeadsign, departingInMinutes: [6, 21, 36], tripIDs: ["full", "short", "loop"])
        store.save(origin, kind: .schedule, stopID: bookmark.stopID, regionID: regionID)
        let destination = try scheduleBody(routeID: key.routeID, headsign: key.tripHeadsign, departingInMinutes: [30, 20], tripIDs: ["full", "loop"])
        store.save(destination, kind: .schedule, stopID: destinationStopID, regionID: regionID)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let loader = BookmarkDataLoader(application: application, delegate: Delegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false, savedArrivals: store)
        await loader.loadDataAndWait()

        #expect(loader.scheduledDepartures(for: key, destinationStopID: destinationStopID).map(\.tripID) == ["full"])
        #expect(loader.scheduledDepartures(for: key).map(\.tripID) == ["full", "short", "loop"])
    }

    /// With no timetable saved for the destination, there is nothing to tell
    /// short turns apart by, so the route and headsign still decide.
    @Test @MainActor
    func `Offline, without the destination's timetable every matching trip stays`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let bookmark = try makeDestinationBookmark(application: application)
        let key = try #require(TripBookmarkKey(bookmark: bookmark))
        let destinationStopID = try #require(bookmark.destinationStopID)
        let regionID = try #require(application.apiService?.regionIdentifier)

        store.save(try savedBody(departingInMinutes: [-10]), stopID: bookmark.stopID, regionID: regionID)
        let origin = try scheduleBody(routeID: key.routeID, headsign: key.tripHeadsign, departingInMinutes: [6, 21], tripIDs: ["full", "short"])
        store.save(origin, kind: .schedule, stopID: bookmark.stopID, regionID: regionID)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let loader = BookmarkDataLoader(application: application, delegate: Delegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false, savedArrivals: store)
        await loader.loadDataAndWait()

        #expect(loader.scheduledDepartures(for: key, destinationStopID: destinationStopID).map(\.tripID) == ["full", "short"])
    }

    /// Online, the destination's timetable is saved next to the origin's, so
    /// it is there the next time the device goes offline.
    @Test @MainActor
    func `A good fetch for a destination bookmark saves the destination's timetable`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let bookmark = try makeDestinationBookmark(application: application)
        let destinationStopID = try #require(bookmark.destinationStopID)
        let regionID = try #require(application.apiService?.regionIdentifier)

        mockArrivals(dataLoader)
        mockSchedule(dataLoader)
        // The trip schedule the live destination arrival needs: a failure is fine here.
        dataLoader.mock(data: Data("{}".utf8), statusCode: 404) { request in
            request.url?.path.contains("/api/where/trip-details") ?? false
        }

        let loader = BookmarkDataLoader(application: application, delegate: Delegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false, savedArrivals: store)
        await loader.loadDataAndWait()

        // The origin's and the destination's timetables are saved by separate
        // tasks that `loadDataAndWait()` doesn't wait for, so wait for both.
        await poll(
            until: {
                self.store.load(kind: .schedule, stopID: destinationStopID, regionID: regionID) != nil
                    && self.store.load(kind: .schedule, stopID: bookmark.stopID, regionID: regionID) != nil
            },
            "the origin's and the destination's timetables were never both saved"
        )
    }

    /// A failed save keeps the destination's previous timetable. Its times
    /// are for another day, so they must not drop today's trips.
    @Test @MainActor
    func `Offline, a destination timetable from another day doesn't drop trips`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let bookmark = try makeDestinationBookmark(application: application)
        let key = try #require(TripBookmarkKey(bookmark: bookmark))
        let destinationStopID = try #require(bookmark.destinationStopID)
        let regionID = try #require(application.apiService?.regionIdentifier)

        store.save(try savedBody(departingInMinutes: [-10]), stopID: bookmark.stopID, regionID: regionID)
        let origin = try scheduleBody(routeID: key.routeID, headsign: key.tripHeadsign, departingInMinutes: [6, 21], tripIDs: ["full", "short"])
        store.save(origin, kind: .schedule, stopID: bookmark.stopID, regionID: regionID)
        let yesterday = try scheduleBody(routeID: key.routeID, headsign: key.tripHeadsign, departingInMinutes: [30 - 1440], tripIDs: ["full"], daysEarlier: 1)
        store.save(yesterday, kind: .schedule, stopID: destinationStopID, regionID: regionID)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))

        let loader = BookmarkDataLoader(application: application, delegate: Delegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false, savedArrivals: store)
        await loader.loadDataAndWait()

        #expect(loader.scheduledDepartures(for: key, destinationStopID: destinationStopID).map(\.tripID) == ["full", "short"])
    }

    /// Departures from an earlier fetch that aren't in the saved set have
    /// left, and must not linger on the card once the stop goes offline.
    @Test @MainActor
    func `Going offline replaces departures from an earlier fetch`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let bookmark = try makeTripBookmark(application: application)
        let key = try #require(TripBookmarkKey(bookmark: bookmark))
        let regionID = try #require(application.apiService?.regionIdentifier)

        let live = try savedBody(departingInMinutes: [10])
        dataLoader.mock(data: live) { [arrivalsPath] request in request.url?.path.contains(arrivalsPath) ?? false }
        mockSchedule(dataLoader)
        let loader = BookmarkDataLoader(application: application, delegate: Delegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false, savedArrivals: store)
        await loader.loadDataAndWait()
        #expect(loader.dataForKey(key).isEmpty == false)

        store.save(try savedBody(departingInMinutes: [-10]), stopID: bookmark.stopID, regionID: regionID)
        // The timetable mock stays: the first fetch's timetable save runs in
        // the background and may still be in flight.
        dataLoader.replaceMappedResponses {
            self.mockArrivalsError($0, URLError(.notConnectedToInternet))
            self.mockSchedule($0)
        }
        await loader.loadDataAndWait()

        #expect(loader.dataForKey(key).isEmpty)
    }

    /// A saved departure must not stay on the card, now looking live, when the
    /// first fetch back online has nothing for the bookmark.
    @Test @MainActor
    func `Back online, an empty response clears the saved departures`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let bookmark = try makeTripBookmark(application: application)
        let key = try #require(TripBookmarkKey(bookmark: bookmark))
        let regionID = try #require(application.apiService?.regionIdentifier)

        store.save(try savedBody(departingInMinutes: [8]), stopID: bookmark.stopID, regionID: regionID)
        mockArrivalsError(dataLoader, URLError(.notConnectedToInternet))
        let loader = BookmarkDataLoader(application: application, delegate: Delegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false, savedArrivals: store)
        await loader.loadDataAndWait()
        #expect(loader.dataForKey(key).isEmpty == false)

        let empty = try savedBody(departingInMinutes: [])
        dataLoader.replaceMappedResponses { [arrivalsPath] mock in
            mock.mock(data: empty) { request in request.url?.path.contains(arrivalsPath) ?? false }
            self.mockSchedule(mock)
        }
        await loader.loadDataAndWait()

        #expect(loader.savedArrivalsDate(forStopID: bookmark.stopID) == nil)
        #expect(loader.dataForKey(key).isEmpty)
    }

    // MARK: - Row model and text

    @Test @MainActor
    func `A stop bookmark row never carries a saved date`() throws {
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let bookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)

        let row = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [], savedArrivalsDate: Date())

        #expect(row.savedArrivalsDate == nil)
    }

    /// The trip schedule a destination arrival needs can't load offline, so the
    /// card must not sit on "Loading arrival…".
    @Test @MainActor
    func `Offline, a destination arrival that can't load shows no spinner`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures
        let arrivalDeparture = try #require(arrivals.first)
        let destinationStop = try #require(try Fixtures.loadSomeStops().first)
        let bookmark = Bookmark(name: "Home", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture, destinationStop: destinationStop)
        try #require(bookmark.hasDestination)

        let live = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [arrivalDeparture], highlightedTripIDs: [], destinationLookup: { _ in .pending })
        let offline = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [arrivalDeparture], highlightedTripIDs: [], savedArrivalsDate: Date(), destinationLookup: { _ in .pending })

        #expect(live.destinationStatus == .loading)
        #expect(offline.destinationStatus == nil)
    }

    /// A destination time cached from an earlier online fetch is an estimate
    /// for live data, so it stays off the card offline like the spinner does.
    @Test @MainActor
    func `Offline, a cached destination arrival is hidden too`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures
        let arrivalDeparture = try #require(arrivals.first)
        let destinationStop = try #require(try Fixtures.loadSomeStops().first)
        let bookmark = Bookmark(name: "Home", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture, destinationStop: destinationStop)
        try #require(bookmark.hasDestination)
        let arrival = DestinationArrival(arrivalDate: Date(), scheduledArrivalDate: Date(), isRealTime: true)

        let live = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [arrivalDeparture], highlightedTripIDs: [], destinationLookup: { _ in .arrives(arrival) })
        let offline = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [arrivalDeparture], highlightedTripIDs: [], savedArrivalsDate: Date(), destinationLookup: { _ in .arrives(arrival) })

        #expect(live.destinationStatus == .arrives(arrival))
        #expect(offline.destinationStatus == nil)
        #expect(offline.destinationStopName == bookmark.destinationStopName)
    }

    @Test @MainActor
    func `The card's saved line names the save time, and VoiceOver hears it first`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures
        let arrivalDeparture = try #require(arrivals.first)
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let bookmark = Bookmark(name: "Work", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture, stop: stop)
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
        let savedAt = Date()
        let time = formatters.timeFormatter.string(from: savedAt)
        // Upcoming: the fixture's own departure is from 2018, and offline a
        // departure that has left isn't shown or spoken.
        let now = Int(Date.timeIntervalSinceReferenceDate)
        let upcoming = try Fixtures.arrivalDeparture(scheduledArrival: now + 600, scheduledDeparture: now + 600, tripID: "upcoming")

        let live = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [arrivalDeparture], highlightedTripIDs: [], hasLoadedArrivalData: true)
        let offline = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [upcoming], highlightedTripIDs: [], savedArrivalsDate: savedAt)
        let offlineEmpty = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [], savedArrivalsDate: savedAt)

        #expect(formatters.savedArrivalsText(for: live) == nil)
        #expect(formatters.savedArrivalsText(for: offline) == "Offline, saved \(time)")
        #expect(formatters.accessibilityValue(for: offline)?.hasPrefix("Offline, saved \(time). ") == true)
        #expect(formatters.accessibilityValue(for: offlineEmpty) == "Offline, saved \(time).")

        // Saved on an earlier day: the date comes first, so the time can't be
        // mistaken for this morning.
        let yesterday = savedAt.addingTimeInterval(-2 * 86_400)
        let older = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [upcoming], highlightedTripIDs: [], savedArrivalsDate: yesterday)
        let olderText = try #require(formatters.savedArrivalsText(for: older))
        #expect(olderText != "Offline, saved \(formatters.timeFormatter.string(from: yesterday))")
        #expect(olderText.hasPrefix("Offline, saved "))
        #expect(olderText.count > "Offline, saved \(time)".count)
    }

    @Test @MainActor
    func `The timetable shows only offline, once the saved departures run out`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures
        let arrivalDeparture = try #require(arrivals.first)
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let trip = Bookmark(name: "Work", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture, stop: stop)
        let stopOnly = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: stop)
        let timetable = [ScheduledDeparture(tripID: "t", routeID: "r", tripHeadsign: "h", route: nil, date: Date().addingTimeInterval(600))]
        let now = Int(Date.timeIntervalSinceReferenceDate)
        let coming = try Fixtures.arrivalDeparture(scheduledArrival: now + 300, scheduledDeparture: now + 300, tripID: "coming")
        let left = try Fixtures.arrivalDeparture(scheduledArrival: now - 120, scheduledDeparture: now - 120, tripID: "left")

        let online = BookmarkRowViewModel(bookmark: trip, arrivalDepartures: [], highlightedTripIDs: [], scheduledDepartures: timetable)
        let offlineWithSaved = BookmarkRowViewModel(bookmark: trip, arrivalDepartures: [coming], highlightedTripIDs: [], savedArrivalsDate: Date(), scheduledDepartures: timetable)
        let offlineRunOut = BookmarkRowViewModel(bookmark: trip, arrivalDepartures: [], highlightedTripIDs: [], savedArrivalsDate: Date(), scheduledDepartures: timetable)
        // Its last saved departure left after the row was built: the timetable
        // takes over when drawn, without waiting for the next refresh.
        let offlineJustLeft = BookmarkRowViewModel(bookmark: trip, arrivalDepartures: [left], highlightedTripIDs: [], savedArrivalsDate: Date(), scheduledDepartures: timetable)
        let stopRow = BookmarkRowViewModel(bookmark: stopOnly, arrivalDepartures: [], highlightedTripIDs: [], savedArrivalsDate: Date(), scheduledDepartures: timetable)

        #expect(online.isShowingTimetable == false)
        #expect(offlineWithSaved.isShowingTimetable == false)
        #expect(offlineRunOut.isShowingTimetable)
        #expect(offlineJustLeft.isShowingTimetable)
        #expect(offlineJustLeft.upcomingScheduledDepartures.map(\.tripID) == ["t"])
        #expect(stopRow.isShowingTimetable == false)
    }

    /// A trip in the saved departures carries a prediction: if it left early,
    /// its timetable time must not bring it back.
    @Test @MainActor
    func `The timetable skips trips that were in the saved departures`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures
        let real = try #require(arrivals.first)
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let trip = Bookmark(name: "Work", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: real, stop: stop)
        let now = Int(Date.timeIntervalSinceReferenceDate)
        let leftEarly = try Fixtures.arrivalDeparture(scheduledArrival: now - 60, scheduledDeparture: now - 60, tripID: "early")
        let timetable = [
            ScheduledDeparture(tripID: "early", routeID: "r", tripHeadsign: "h", route: nil, date: Date().addingTimeInterval(120)),
            ScheduledDeparture(tripID: "next", routeID: "r", tripHeadsign: "h", route: nil, date: Date().addingTimeInterval(900))
        ]

        let row = BookmarkRowViewModel(bookmark: trip, arrivalDepartures: [leftEarly], highlightedTripIDs: [], savedArrivalsDate: Date(), scheduledDepartures: timetable)

        #expect(row.upcomingScheduledDepartures.map(\.tripID) == ["next"])
    }

    @Test @MainActor
    func `A timetable card says so, and VoiceOver reads the scheduled times`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures
        let arrivalDeparture = try #require(arrivals.first)
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let bookmark = Bookmark(name: "Work", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture, stop: stop)
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
        let timetable = [6.5, 21.5, 36.5].enumerated().map { index, minutes in
            ScheduledDeparture(tripID: "t\(index)", routeID: "r", tripHeadsign: "h", route: nil, date: Date().addingTimeInterval(minutes * 60))
        }

        let row = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [], savedArrivalsDate: Date(), scheduledDepartures: timetable)
        let value = try #require(formatters.accessibilityValue(for: row))

        #expect(formatters.savedArrivalsText(for: row) == "Offline, scheduled times")
        #expect(value.hasPrefix("Offline, scheduled times. scheduled to depart in 6 minutes at "))
        #expect(value.hasSuffix("Following two departures in 21 minutes and 36 minutes."))
    }

    /// Offline, the card redraws between refreshes, so a saved departure that
    /// leaves in between must go at once rather than read "-1m".
    @Test @MainActor
    func `Offline, a saved departure that has left drops out before the next refresh`() throws {
        let now = Int(Date.timeIntervalSinceReferenceDate)
        let left = try Fixtures.arrivalDeparture(scheduledArrival: now - 120, scheduledDeparture: now - 120, tripID: "left")
        let coming = try Fixtures.arrivalDeparture(scheduledArrival: now + 600, scheduledDeparture: now + 600, tripID: "coming")
        let real = try #require(try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: fixtureFile).arrivalsAndDepartures.first)
        let stop = try #require(try Fixtures.loadSomeStops().first)
        let bookmark = Bookmark(name: "Work", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: real, stop: stop)

        let online = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [left, coming], highlightedTripIDs: [])
        let offline = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [left, coming], highlightedTripIDs: [], savedArrivalsDate: Date())

        #expect(online.upcomingArrivalDepartures.map(\.tripID) == ["left", "coming"])
        #expect(offline.upcomingArrivalDepartures.map(\.tripID) == ["coming"])
    }
}
