//
//  BookmarkArrivalsLoaderTests.swift
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

@Suite(.serialized)
final class BookmarkArrivalsLoaderTests: OBATestCase {

    // `nonisolated`: recorded from `MockDataLoaderMatcher` closures, which run
    // wherever the request is issued (not necessarily the main actor). The
    // test target defaults to main-actor isolation, which would be wrong here
    // — see the same rationale on `MockDataLoader` itself.
    private nonisolated final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var paths = [String]()

        func record(_ path: String) {
            lock.lock(); defer { lock.unlock() }
            paths.append(path)
        }

        var all: [String] {
            lock.lock(); defer { lock.unlock() }
            return paths
        }
    }

    private let arrivalsPath = "/api/where/arrivals-and-departures-for-stop"

    private func mockArrivals(_ dataLoader: MockDataLoader, log: RequestLog, failingStopID: String? = nil) {
        if let failingStopID {
            dataLoader.mock(data: Data("{}".utf8), statusCode: 500) { request in
                request.url?.path.contains(failingStopID) ?? false
            }
        }
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { [arrivalsPath] request in
            guard let path = request.url?.path, path.contains(arrivalsPath) else { return false }
            if let failingStopID, path.contains(failingStopID) { return false }
            log.record(path)
            return true
        }
    }

    @Test func `Two requests at one stop make one network call`() async {
        let dataLoader = MockDataLoader(testName: name)
        let log = RequestLog()
        mockArrivals(dataLoader, log: log)
        let service = buildRESTService(dataLoader: dataLoader)

        let requests = [
            BookmarkArrivalsRequest(stopID: "1_75414"),
            BookmarkArrivalsRequest(stopID: "1_75414", tripKey: TripBookmarkKey(stopID: "1_75414", routeShortName: "X", routeID: "1_X", tripHeadsign: "Y")),
            BookmarkArrivalsRequest(stopID: "1_10914")
        ]

        var delivered = [StopID]()
        for await (stopID, _) in BookmarkArrivalsLoader().arrivals(for: requests, using: service) {
            delivered.append(stopID)
        }

        #expect(log.all.count == 2)
        #expect(Set(delivered) == ["1_75414", "1_10914"])
        #expect(delivered.count == 2)
    }

    @Test func `No requests finishes immediately with no network calls`() async {
        let dataLoader = MockDataLoader(testName: name)
        let log = RequestLog()
        mockArrivals(dataLoader, log: log)

        var count = 0
        for await _ in BookmarkArrivalsLoader().arrivals(for: [], using: buildRESTService(dataLoader: dataLoader)) {
            count += 1
        }

        #expect(count == 0)
        #expect(log.all.isEmpty)
    }

    /// One stop failing must not cost the others their data.
    @Test func `A failing stop yields a failure and the rest still succeed`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockArrivals(dataLoader, log: RequestLog(), failingStopID: "1_BROKEN")
        let service = buildRESTService(dataLoader: dataLoader)

        var results = [StopID: Bool]()
        let requests = [BookmarkArrivalsRequest(stopID: "1_BROKEN"), BookmarkArrivalsRequest(stopID: "1_75414")]
        for await (stopID, result) in BookmarkArrivalsLoader().arrivals(for: requests, using: service) {
            if case .success = result { results[stopID] = true } else { results[stopID] = false }
        }

        #expect(results == ["1_BROKEN": false, "1_75414": true])
    }

    // The fixture's departures are years old, so filtering by `.matching` on it
    // alone leaves an empty (and vacuously-passing) list — `temporalState`
    // reads `Date()`. Built instead from `Fixtures.arrivalDeparture`, whose
    // `.deferredToDate` decode lands in the 2050s (see its doc comment), so
    // these are genuinely upcoming, and out of order here so the sort is
    // actually exercised.
    @Test func `A stop request matches every upcoming departure, soonest first`() throws {
        let stopID = "1_10914"
        let now = Int(Date.timeIntervalSinceReferenceDate)
        let soonest = try Fixtures.arrivalDeparture(scheduledArrival: now + 60, scheduledDeparture: now + 60, stopID: stopID, tripID: "trip_soonest")
        let soon = try Fixtures.arrivalDeparture(scheduledArrival: now + 300, scheduledDeparture: now + 300, stopID: stopID, tripID: "trip_soon")
        let later = try Fixtures.arrivalDeparture(scheduledArrival: now + 900, scheduledDeparture: now + 900, stopID: stopID, tripID: "trip_later")

        let matched = BookmarkArrivalsRequest(stopID: stopID).matching([later, soon, soonest])

        #expect(matched.map(\.tripID) == ["trip_soonest", "trip_soon", "trip_later"])
        #expect(matched.allSatisfy { $0.temporalState != .past })
        #expect(matched.map(\.arrivalDepartureDate) == matched.map(\.arrivalDepartureDate).sorted())
    }

    @Test func `A trip request matches only its own trip key`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: "arrivals-and-departures-for-stop-1_10914.json").arrivalsAndDepartures
        let first = try #require(arrivals.first)
        let key = TripBookmarkKey(arrivalDeparture: first)

        let matched = BookmarkArrivalsRequest(stopID: first.stopID, tripKey: key).matching(arrivals)

        #expect(matched.isEmpty == false)
        #expect(matched.allSatisfy { TripBookmarkKey(arrivalDeparture: $0) == key })
    }

    @Test func `Departures by bookmark omits a bookmark whose stop failed`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let stops = try Fixtures.loadSomeStops()
        let good = Bookmark(name: "Good", regionIdentifier: pugetSoundRegionIdentifier, stop: stops[0])
        let bad = Bookmark(name: "Bad", regionIdentifier: pugetSoundRegionIdentifier, stop: stops[1])
        mockArrivals(dataLoader, log: RequestLog(), failingStopID: stops[1].id)

        let result = await BookmarkArrivalsLoader().departuresByBookmark(for: [good, bad], using: buildRESTService(dataLoader: dataLoader))

        #expect(result[good.id] != nil)
        #expect(result[bad.id] == nil)
    }

    @Test func `TripBookmarkKey initialization from watch bookmark`() {
        let tripBookmark = WatchBookmark(
            id: UUID(),
            name: "Trip Bookmark",
            regionIdentifier: 1,
            stopID: "1_100",
            stopName: "Stop",
            latitude: 47.6,
            longitude: -122.3,
            isFavorite: true,
            routeID: "1_40",
            routeShortName: "40",
            tripHeadsign: "Downtown"
        )
        let key = TripBookmarkKey(watchBookmark: tripBookmark)
        #expect(key != nil)
        #expect(key?.stopID == "1_100")
        #expect(key?.routeID == "1_40")
        #expect(key?.routeShortName == "40")
        #expect(key?.tripHeadsign == "Downtown")

        let stopBookmark = WatchBookmark(
            id: UUID(),
            name: "Stop Bookmark",
            regionIdentifier: 1,
            stopID: "1_100",
            stopName: "Stop",
            latitude: 47.6,
            longitude: -122.3,
            isFavorite: false
        )
        #expect(TripBookmarkKey(watchBookmark: stopBookmark) == nil)
    }

    @Test func `Standalone service targets the region's base URL`() async {
        let service = RESTAPIService.standalone(region: Fixtures.pugetSoundRegion, apiKey: "key", appVersion: "1.0", uuid: "uuid")
        #expect(await service.configuration.baseURL == Fixtures.pugetSoundRegion.OBABaseURL)
        #expect(await service.configuration.regionIdentifier == Fixtures.pugetSoundRegion.regionIdentifier)
    }

    @Test func `Standalone service performs a single attempt against a loader that returns 500`() async {
        let mockLoader = MockDataLoader(testName: name)
        mockLoader.mock(data: Data("{}".utf8), statusCode: 500) { _ in true }
        let countingLoader = CountingDataLoader(mockLoader)

        let service = RESTAPIService.standalone(
            region: Fixtures.pugetSoundRegion,
            apiKey: "key",
            appVersion: "1.0",
            uuid: "uuid",
            dataLoader: countingLoader
        )
        #expect(service.retryPolicy == .disabled)

        do {
            _ = try await service.getStop(id: "1_75414")
            Issue.record("Expected request to fail with 500")
        } catch {
            // Expected
        }

        #expect(countingLoader.callCount == 1)
    }

    @Test func `BookmarkArrivalsRequest matching filters past departures and sorts upcoming arrivals soonest first`() throws {
        let now = Int(Date.timeIntervalSinceReferenceDate)
        let stopID = "1_100"

        let past = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: now - 3600,
            scheduledDeparture: now - 3600,
            stopSequence: 1,
            stopID: stopID,
            tripID: "trip_past"
        )
        let upcomingLater = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: now + 600,
            scheduledDeparture: now + 600,
            stopSequence: 2,
            stopID: stopID,
            tripID: "trip_later"
        )
        let upcomingSoon = try Fixtures.arrivalDeparture(
            predicted: false,
            scheduledArrival: now + 300,
            scheduledDeparture: now + 300,
            stopSequence: 3,
            stopID: stopID,
            tripID: "trip_soon"
        )

        #expect(past.temporalState == .past)
        #expect(upcomingLater.temporalState != .past)
        #expect(upcomingSoon.temporalState != .past)

        let request = BookmarkArrivalsRequest(stopID: stopID)
        let matched = request.matching([upcomingLater, past, upcomingSoon])

        #expect(matched.count == 2)
        #expect(matched.map(\.tripID) == ["trip_soon", "trip_later"])
        #expect(matched.first?.arrivalDepartureDate == upcomingSoon.arrivalDepartureDate)
        #expect(matched.last?.arrivalDepartureDate == upcomingLater.arrivalDepartureDate)
    }

    @Test func `BookmarkArrivalsRequest matching with non matching tripKey returns empty array`() throws {
        let arrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        ).arrivalsAndDepartures
        let first = try #require(arrivals.first)

        let unmatchedKey = TripBookmarkKey(
            stopID: first.stopID,
            routeShortName: "NonExistentRoute",
            routeID: "1_999999",
            tripHeadsign: "Nowhere"
        )
        let request = BookmarkArrivalsRequest(stopID: first.stopID, tripKey: unmatchedKey)

        let matched = request.matching(arrivals)
        #expect(matched.isEmpty)
    }

    // MARK: - Saved timetables are matched by day in the loader's time zone (#2018)

    /// Pacific/Kiritimati (UTC+14): the agency zone for these tests. It sits
    /// far enough from the device zone on CI (UTC) and on a developer Mac
    /// that the agency day and the device day disagree for the instants
    /// below — so these tests fail with the old `Calendar.current` checks
    /// and pass with the loader's time zone.
    private let agencyZone = TimeZone(identifier: "Pacific/Kiritimati")!

    /// The start of the agency day containing now.
    private var agencyMidnight: Date {
        var calendar = Calendar.current
        calendar.timeZone = agencyZone
        return calendar.startOfDay(for: Date())
    }

    /// `body` with every epoch-millisecond time in it moved by `shift`
    /// milliseconds — the same helper `SavedTimetableHeadsignTests` uses,
    /// so a fixture's timetable stays self-consistent when its `date` moves.
    private func shifted(_ body: Data, by milliseconds: Int64) throws -> Data {
        func shift(_ value: Any) -> Any {
            switch value {
            case let dictionary as [String: Any]: return dictionary.mapValues(shift)
            case let array as [Any]: return array.map(shift)
            case let number as NSNumber where number.int64Value > 1_000_000_000_000: return number.int64Value + milliseconds
            default: return value
            }
        }
        return try JSONSerialization.data(withJSONObject: shift(try JSONSerialization.jsonObject(with: body)))
    }

    /// A store holding stop 1_75403's schedule fixture with its `date` moved
    /// to `target`, plus the directory it lives in (the caller removes it).
    private func storeWithScheduleDated(_ target: Date) throws -> (store: SavedArrivalsStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BookmarkArrivalsLoaderTests-\(UUID().uuidString)")
        let store = SavedArrivalsStore(directory: directory)
        let body = Fixtures.loadData(file: "schedule-for-stop_1_75403-route-72.json")
        let schedule = try buildRESTService().decodeKeptBody(ScheduleForStop.self, from: body).entry
        let shift = Int64(target.timeIntervalSince(schedule.date) * 1000)
        store.save(try shifted(body, by: shift), kind: .schedule, stopID: "1_75403", regionID: pugetSoundRegionIdentifier)
        return (store, directory)
    }

    @Test func `Saved arrival times match by the agency zone day, not the device day`() throws {
        // 01:00 and 23:00 on the same agency day — but different device
        // (UTC) days: the timetable must match.
        let scheduleDate = agencyMidnight.addingTimeInterval(3600)
        let serviceDate = agencyMidnight.addingTimeInterval(23 * 3600)

        let (store, directory) = try storeWithScheduleDated(scheduleDate)
        defer { try? FileManager.default.removeItem(at: directory) }

        let times = BookmarkArrivalsLoader(savedArrivals: store, timeZone: agencyZone)
            .savedArrivalTimes(stopID: "1_75403", serviceDate: serviceDate, using: buildRESTService())

        #expect(times != nil)
        #expect(times?.isEmpty == false)
    }

    @Test func `Saved arrival times ignore a timetable from another agency day`() throws {
        // 23:00 on the previous agency day and 01:00 today — the same
        // device (UTC) day, but the timetable is yesterday's in the agency
        // zone, so it must not match.
        let scheduleDate = agencyMidnight.addingTimeInterval(-3600)
        let serviceDate = agencyMidnight.addingTimeInterval(3600)

        let (store, directory) = try storeWithScheduleDated(scheduleDate)
        defer { try? FileManager.default.removeItem(at: directory) }

        let times = BookmarkArrivalsLoader(savedArrivals: store, timeZone: agencyZone)
            .savedArrivalTimes(stopID: "1_75403", serviceDate: serviceDate, using: buildRESTService())

        #expect(times == nil)
    }

    /// A data loader that records every schedule-for-stop fetch it serves.
    private func scheduleFetchLog(dataLoader: MockDataLoader, body: Data) -> RequestLog {
        let log = RequestLog()
        dataLoader.mock(data: body) { request in
            guard let path = request.url?.path, path.contains("/api/where/schedule-for-stop") else { return false }
            log.record(path)
            return true
        }
        return log
    }

    @Test func `Save-today check uses the agency zone day`() async throws {
        // Saved at 01:00 agency today — yesterday in the device (UTC) day.
        // No refetch: the timetable is already today's in the agency zone.
        let savedAt = agencyMidnight.addingTimeInterval(3600)

        let directory = FileManager.default.temporaryDirectory.appending(path: "BookmarkArrivalsLoaderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedArrivalsStore(directory: directory)
        let body = Fixtures.loadData(file: "schedule-for-stop_1_75403-route-72.json")
        store.save(body, kind: .schedule, stopID: "1_75403", regionID: pugetSoundRegionIdentifier, savedAt: savedAt)

        let dataLoader = MockDataLoader(testName: name)
        let log = scheduleFetchLog(dataLoader: dataLoader, body: body)

        await BookmarkArrivalsLoader(savedArrivals: store, timeZone: agencyZone)
            .saveTodaysScheduleIfNeeded(stopID: "1_75403", using: buildRESTService(dataLoader: dataLoader))

        #expect(log.all.isEmpty)
    }

    @Test func `Save-today check refetches when the saved day is yesterday in the agency zone`() async throws {
        // Saved at 23:00 agency yesterday — today in the device (UTC) day.
        // The timetable is stale in the agency zone, so it must refetch.
        let savedAt = agencyMidnight.addingTimeInterval(-3600)

        let directory = FileManager.default.temporaryDirectory.appending(path: "BookmarkArrivalsLoaderTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedArrivalsStore(directory: directory)
        let body = Fixtures.loadData(file: "schedule-for-stop_1_75403-route-72.json")
        store.save(body, kind: .schedule, stopID: "1_75403", regionID: pugetSoundRegionIdentifier, savedAt: savedAt)

        let dataLoader = MockDataLoader(testName: name)
        let log = scheduleFetchLog(dataLoader: dataLoader, body: body)

        await BookmarkArrivalsLoader(savedArrivals: store, timeZone: agencyZone)
            .saveTodaysScheduleIfNeeded(stopID: "1_75403", using: buildRESTService(dataLoader: dataLoader))

        #expect(log.all.count == 1)
    }
}
