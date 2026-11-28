//
//  BookmarkEntityQueryTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite
final class BookmarkEntityQueryTests: OBATestCase {

    override init() async throws {
        try await super.init()
    }

    private func makeQuery() -> BookmarkEntityQuery {
        let suite = userDefaultsSuiteName
        return BookmarkEntityQuery { UserDefaults(suiteName: suite) }
    }

    private func setCurrentRegion(_ regionID: Int?) {
        if let regionID {
            userDefaults.set(regionID, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        }
    }

    private func makeStop(id: StopID = "1_10914", name: String = "Pine St", regionID: Int = 1) -> Stop {
        Stop(
            id: id,
            name: name,
            code: "10914",
            location: CLLocation(latitude: 47.6097, longitude: -122.3422),
            regionIdentifier: regionID
        )
    }

    private func makeTripBookmark(name: String, stop: Stop, regionID: Int) throws -> Bookmark {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(name: name, regionIdentifier: regionID, arrivalDeparture: arrivalDeparture, stop: stop)
        try #require(bookmark.isTripBookmark)
        return bookmark
    }

    @Test func `Missing app group or nil UserDefaults returns empty results`() async throws {
        let query = BookmarkEntityQuery { nil }

        #expect(try await query.suggestedEntities().isEmpty)
        #expect(try await query.entities(for: [UUID()]).isEmpty)
        #expect(try await query.entities(matching: "49").isEmpty)
    }

    @Test func `Missing or non-integer region identifier returns empty results`() async throws {
        let stop = makeStop(regionID: 1)
        let trip = try makeTripBookmark(name: "49 to Downtown", stop: stop, regionID: 1)
        let store = UserDefaultsStore(userDefaults: userDefaults)
        store.add(trip)

        setCurrentRegion(nil)
        let query = makeQuery()

        #expect(try await query.suggestedEntities().isEmpty)
        #expect(try await query.entities(for: [trip.id]).isEmpty)
        #expect(try await query.entities(matching: "49").isEmpty)

        userDefaults.set("1", forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        #expect(try await query.suggestedEntities().isEmpty)
        #expect(try await query.entities(for: [trip.id]).isEmpty)
    }

    @Test func `Empty store and deleted bookmarks return empty results`() async throws {
        setCurrentRegion(1)
        let query = makeQuery()

        #expect(try await query.suggestedEntities().isEmpty)
        #expect(try await query.entities(for: [UUID()]).isEmpty)
        #expect(try await query.entities(matching: "Downtown").isEmpty)

        let store = UserDefaultsStore(userDefaults: userDefaults)
        let trip = try makeTripBookmark(name: "49 to Downtown", stop: makeStop(regionID: 1), regionID: 1)
        store.add(trip)
        #expect(try await query.entities(for: [trip.id]).map(\.id) == [trip.id])

        store.delete(bookmark: trip)
        #expect(try await query.suggestedEntities().isEmpty)
        #expect(try await query.entities(for: [trip.id]).isEmpty)
        #expect(try await query.entities(matching: "49").isEmpty)
    }

    @Test func `Only trip bookmarks in current region are offered and strictly looked up`() async throws {
        setCurrentRegion(1)
        let store = UserDefaultsStore(userDefaults: userDefaults)

        let currentStop = makeStop(id: "1_100", name: "3rd & Pine", regionID: 1)
        let otherRegionStop = makeStop(id: "2_200", name: "Rynek", regionID: 2)

        let wholeStopCurrent = Bookmark(name: "Whole Stop Pine", regionIdentifier: 1, stop: currentStop)
        let tripCurrent = try makeTripBookmark(name: "49 to Downtown", stop: currentStop, regionID: 1)
        let tripOtherRegion = try makeTripBookmark(name: "52 to Centrum", stop: otherRegionStop, regionID: 2)

        store.add(wholeStopCurrent)
        store.add(tripCurrent)
        store.add(tripOtherRegion)

        let query = makeQuery()
        let suggested = try await query.suggestedEntities()
        #expect(suggested.map(\.id) == [tripCurrent.id])
        #expect(suggested.map(\.name) == ["49 to Downtown"])

        let lookedUp = try await query.entities(for: [wholeStopCurrent.id, tripOtherRegion.id, tripCurrent.id])
        #expect(lookedUp.map(\.id) == [tripCurrent.id])

        #expect(try await query.entities(matching: "Whole Stop").isEmpty)
        #expect(try await query.entities(matching: "Centrum").isEmpty)
        #expect(try await query.entities(matching: "Downtown").map(\.id) == [tripCurrent.id])
    }

    @Test func `Unicode, accented, and Polish diacritic names match case- and diacritic-insensitively`() async throws {
        setCurrentRegion(2)
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let stop = makeStop(id: "2_1201", name: "Plac Wolności", regionID: 2)

        let polish = try makeTripBookmark(name: "Zażółć gęślą jaźń — 52", stop: stop, regionID: 2)
        let emoji = try makeTripBookmark(name: "Łódź Kaliska 🚌", stop: stop, regionID: 2)
        let accented = try makeTripBookmark(name: "Café Express", stop: stop, regionID: 2)
        store.add(polish)
        store.add(emoji)
        store.add(accented)

        let query = makeQuery()
        // Combining diacritics (ą, ć, ę, ń, ó, ś, ź, ż, é) fold under localizedStandardContains;
        // stroked Ł/ł has no Unicode decomposition and matches case-insensitively with the stroke.
        #expect(try await query.entities(matching: "gesla").map(\.name) == ["Zażółć gęślą jaźń — 52"])
        #expect(try await query.entities(matching: "GĘŚLĄ").map(\.id) == [polish.id])
        #expect(try await query.entities(matching: "łódź").map(\.id) == [emoji.id])
        #expect(try await query.entities(matching: "ŁODZ").map(\.id) == [emoji.id])
        #expect(try await query.entities(matching: "cafe").map(\.id) == [accented.id])
    }

    @Test func `Unknown UUIDs are dropped and entities(for:) preserves requested order`() async throws {
        setCurrentRegion(1)
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let stop = makeStop(regionID: 1)

        let first = try makeTripBookmark(name: "Route 8", stop: stop, regionID: 1)
        let second = try makeTripBookmark(name: "Route 49", stop: stop, regionID: 1)
        store.add(first)
        store.add(second)

        let query = makeQuery()
        let resolved = try await query.entities(for: [second.id, UUID(), first.id])
        #expect(resolved.map(\.id) == [second.id, first.id])
        #expect(resolved.map(\.name) == ["Route 49", "Route 8"])
    }

    @Test func `Search matching truncates at 20 results while suggestedEntities returns all`() async throws {
        setCurrentRegion(1)
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let stop = makeStop(regionID: 1)

        let bookmarks = try (1...25).map { index in
            try makeTripBookmark(name: "Route \(index) Express", stop: stop, regionID: 1)
        }
        store.bookmarks = bookmarks

        let query = makeQuery()
        let suggested = try await query.suggestedEntities()
        #expect(suggested.map(\.id) == bookmarks.map(\.id))

        let matched = try await query.entities(matching: "Route")
        #expect(matched.count == BookmarkIntentMapping.searchResultLimit)
        #expect(matched.map(\.id) == bookmarks.prefix(20).map(\.id))
        #expect(try await query.entities(matching: "Nonexistent").isEmpty)
    }
}
