//
//  SavedTimetableHeadsignTests.swift
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

/// Offline timetables for routes whose arrivals carry a stop's own headsign.
/// At stop 1_75403, route 72's arrivals say "University District", but its
/// timetable and trips say "University District Lake City". The fixtures are
/// the server's real responses for the stop, fetched together.
@Suite(.serialized)
final class SavedTimetableHeadsignTests: OBATestCase {

    private let arrivalsFixture = "arrivals-and-departures-for-stop-1_75403-route-72.json"
    private let scheduleFixture = "schedule-for-stop_1_75403-route-72.json"

    private var directory: URL!
    private var store: SavedArrivalsStore!

    override init() async throws {
        try await super.init()
        directory = FileManager.default.temporaryDirectory.appending(path: "SavedTimetableHeadsignTests-\(UUID().uuidString)")
        store = SavedArrivalsStore(directory: directory)
    }

    isolated deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    private final class Delegate: NSObject, BookmarkDataDelegate {
        func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {}
    }

    /// `body` with every epoch time in it moved by `shift` milliseconds.
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

    /// Offline at stop 1_75403, with its arrivals and timetable saved and moved
    /// in time so every saved departure left 10 minutes ago: the timetable
    /// departures each route's bookmark gets.
    @MainActor
    private func offlineTimetable(forRoute routeShortName: String) async throws -> (key: TripBookmarkKey, departures: [ScheduledDeparture], timetable: [ScheduledDeparture]) {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: OperationQueue(), dataLoader: dataLoader)
        let regionID = try #require(application.apiService?.regionIdentifier)

        let arrivals = try Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: arrivalsFixture).arrivalsAndDepartures
        let lastDeparture = try #require(arrivals.map { max($0.scheduledDeparture, $0.predictedDeparture ?? $0.scheduledDeparture) }.max())
        let shift = Int64(Date().addingTimeInterval(-600).timeIntervalSince(lastDeparture) * 1000)
        let arrivalsBody = try shifted(Fixtures.loadData(file: arrivalsFixture), by: shift)
        let scheduleBody = try shifted(Fixtures.loadData(file: scheduleFixture), by: shift)

        let arrivalDeparture = try #require(arrivals.first { $0.routeShortName == routeShortName })
        let bookmark = Bookmark(name: routeShortName, regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDeparture)
        application.userDataStore.add(bookmark, to: nil)
        let key = try #require(TripBookmarkKey(bookmark: bookmark))

        store.save(arrivalsBody, stopID: bookmark.stopID, regionID: regionID)
        store.save(scheduleBody, kind: .schedule, stopID: bookmark.stopID, regionID: regionID)
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: URLError(.notConnectedToInternet)) { request in
            request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        })

        let loader = BookmarkDataLoader(application: application, delegate: Delegate(), bookmarkProvider: { [bookmark] }, autoRefreshes: false, savedArrivals: store)
        await loader.loadDataAndWait()
        #expect(loader.dataForKey(key).isEmpty)

        let timetable = try #require(try application.apiService?.decodeKeptBody(ScheduleForStop.self, from: scheduleBody).entry.scheduledDepartures)
        return (key, loader.scheduledDepartures(for: key), timetable)
    }

    @Test @MainActor
    func `Offline, a route with the stop's own headsign still gets its timetable`() async throws {
        let (key, departures, timetable) = try await offlineTimetable(forRoute: "72")
        #expect(key.tripHeadsign == "University District")

        let expected = timetable.filter { $0.routeID == key.routeID && $0.minutes >= 0 }
        #expect(expected.isEmpty == false)
        #expect(expected.allSatisfy { $0.tripHeadsign == "University District Lake City" })
        #expect(departures.map(\.tripID) == expected.map(\.tripID))
    }

    @Test @MainActor
    func `Offline, a route whose headsigns agree keeps only its own timetable`() async throws {
        let (key, departures, timetable) = try await offlineTimetable(forRoute: "67")

        let expected = timetable.filter { $0.routeID == key.routeID && $0.minutes >= 0 }
        #expect(expected.isEmpty == false)
        #expect(departures.map(\.tripID) == expected.map(\.tripID))
    }
}
