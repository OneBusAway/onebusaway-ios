//
//  StopEntityQueryTests.swift
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
final class StopEntityQueryTests: OBATestCase {

    override init() async throws {
        try await super.init()
    }

    private func makeQuery() -> StopEntityQuery {
        let suite = userDefaultsSuiteName
        return StopEntityQuery { UserDefaults(suiteName: suite) }
    }

    private func setCurrentRegion(_ regionID: Int?) {
        if let regionID {
            userDefaults.set(regionID, forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        }
    }

    private func makeStop(id: StopID, name: String, code: String = "", regionID: Int) -> Stop {
        Stop(
            id: id,
            name: name,
            code: code,
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
        let query = StopEntityQuery { nil }

        #expect(try await query.suggestedEntities().isEmpty)
        #expect(try await query.entities(for: ["region_1_stop_1_75403"]).isEmpty)
        #expect(try await query.entities(matching: "Pine").isEmpty)
    }

    @Test func `Missing or non-integer region identifier empties suggestions and search while entities(for:) resolves`() async throws {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let pine = makeStop(id: "1_75403", name: "3rd Ave & Pine St", code: "75403", regionID: 1)
        store.bookmarks = [Bookmark(name: "Pine", regionIdentifier: 1, stop: pine)]

        setCurrentRegion(nil)
        let query = makeQuery()

        #expect(try await query.suggestedEntities().isEmpty)
        #expect(try await query.entities(matching: "Pine").isEmpty)

        let resolved = try await query.entities(for: ["region_1_stop_1_75403", "region_2_stop_2_999"])
        #expect(resolved.map(\.id) == ["region_1_stop_1_75403", "region_2_stop_2_999"])
        #expect(resolved.map(\.name) == ["3rd Ave & Pine St", nil])
        #expect(resolved.last?.title == "Stop 2_999")

        userDefaults.set("1", forKey: RegionsService.currentRegionIdentifierUserDefaultsKey)
        #expect(try await query.suggestedEntities().isEmpty)
    }

    @Test func `Empty store yields empty suggestions and fallback entities for valid identifiers`() async throws {
        setCurrentRegion(1)
        let query = makeQuery()

        #expect(try await query.suggestedEntities().isEmpty)
        #expect(try await query.entities(matching: "Pine").isEmpty)

        let fallback = try await query.entities(for: ["region_1_stop_1_75403"])
        #expect(fallback.count == 1)
        #expect(fallback.first?.regionID == 1)
        #expect(fallback.first?.stopID == "1_75403")
        #expect(fallback.first?.name == nil)
        #expect(fallback.first?.title == "Stop 1_75403")
    }

    @Test func `Whole-stop and trip bookmarks convert and deduplicate bookmarked above recent tiers`() async throws {
        setCurrentRegion(1)
        let store = UserDefaultsStore(userDefaults: userDefaults)

        let stopA = makeStop(id: "1_100", name: "Pine St & 3rd Ave", regionID: 1)
        let stopB = makeStop(id: "1_200", name: "Pike St & 4th Ave", regionID: 1)
        let stopC = makeStop(id: "1_300", name: "Union St & 5th Ave", regionID: 1)
        let otherRegion = makeStop(id: "2_400", name: "Plac Wolności", regionID: 2)

        let wholeBookmark = Bookmark(name: "Whole", regionIdentifier: 1, stop: stopA)
        let tripBookmark = try makeTripBookmark(name: "49 to Downtown", stop: stopB, regionID: 1)
        let duplicateTripOnA = try makeTripBookmark(name: "8 to Uptown", stop: stopA, regionID: 1)
        let otherRegionBookmark = Bookmark(name: "Away", regionIdentifier: 2, stop: otherRegion)

        store.bookmarks = [wholeBookmark, tripBookmark, duplicateTripOnA, otherRegionBookmark]
        store.recentStops = [stopC, stopA, stopC, stopB, otherRegion]

        let query = makeQuery()
        let suggested = try await query.suggestedEntities()
        #expect(suggested.map(\.id) == [
            "region_1_stop_1_100",
            "region_1_stop_1_200",
            "region_1_stop_1_300",
        ])

        // Deleting a bookmark promotes its stop down or removes it if not in recents.
        store.delete(bookmark: tripBookmark)
        store.recentStops = [stopC]
        let afterDelete = try await query.suggestedEntities()
        #expect(afterDelete.map(\.id) == [
            "region_1_stop_1_100",
            "region_1_stop_1_300",
        ])
    }

    @Test func `Unicode, Polish diacritics, and anchored stop codes match deterministically`() async throws {
        setCurrentRegion(2)
        let store = UserDefaultsStore(userDefaults: userDefaults)

        let polish = makeStop(id: "2_1201", name: "Plac Wolności", code: "1201", regionID: 2)
        let zabikowo = makeStop(id: "2_1202", name: "Żabikowo Pętla 🚊", code: "9912", regionID: 2)
        let cafe = makeStop(id: "2_1203", name: "Café Central", code: "", regionID: 2)
        store.recentStops = [polish, zabikowo, cafe]

        let query = makeQuery()
        #expect(try await query.entities(matching: "wolnosci").map(\.id) == ["region_2_stop_2_1201"])
        #expect(try await query.entities(matching: "ZABIKOWO").map(\.id) == ["region_2_stop_2_1202"])
        #expect(try await query.entities(matching: "cafe").map(\.id) == ["region_2_stop_2_1203"])

        // Code matching is anchored at the start.
        #expect(try await query.entities(matching: "120").map(\.id) == ["region_2_stop_2_1201"])
        #expect(try await query.entities(matching: "201").isEmpty)
        #expect(try await query.entities(matching: "zzz").isEmpty)
    }

    @Test func `Stop IDs containing _stop_ survive round-trip storage and lookup`() async throws {
        setCurrentRegion(1)
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let customStop = makeStop(id: "40_stop_7", name: "Transfer Hub", code: "407", regionID: 1)
        store.bookmarks = [Bookmark(name: "Hub", regionIdentifier: 1, stop: customStop)]

        let query = makeQuery()
        let suggested = try await query.suggestedEntities()
        #expect(suggested.map(\.id) == ["region_1_stop_40_stop_7"])
        #expect(suggested.first?.stopID == "40_stop_7")

        let storedAndFallback = try await query.entities(for: [
            "region_1_stop_40_stop_7",
            "region_1_stop_part1_stop_part2_stop_part3",
        ])
        #expect(storedAndFallback.map(\.stopID) == ["40_stop_7", "part1_stop_part2_stop_part3"])
        #expect(storedAndFallback.map(\.name) == ["Transfer Hub", nil])
    }

    @Test func `Corrupted and unparseable identifiers are dropped while valid ones preserve order`() async throws {
        setCurrentRegion(1)
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let pine = makeStop(id: "1_75403", name: "3rd Ave & Pine St", regionID: 1)
        store.recentStops = [pine]

        let query = makeQuery()
        let invalidIDs = ["", "foo", "region_x_stop_1", "region_1_stop_", "region__stop_1", "1_75403"]
        #expect(try await query.entities(for: invalidIDs).isEmpty)

        let mixed = try await query.entities(for: [
            "region_1_stop_missing",
            "region_1_stop_",
            "foo",
            "region_1_stop_1_75403",
        ])
        #expect(mixed.map(\.id) == ["region_1_stop_missing", "region_1_stop_1_75403"])
        #expect(mixed.map(\.name) == [nil, "3rd Ave & Pine St"])
    }

    @Test func `Search matching orders bookmarked before recent and truncates at 20 results`() async throws {
        setCurrentRegion(1)
        let store = UserDefaultsStore(userDefaults: userDefaults)

        let bookmarkedStops = (1...5).map { index in
            makeStop(id: "1_b\(index)", name: "Main St Bookmarked \(index)", regionID: 1)
        }
        let recentStops = (1...22).map { index in
            makeStop(id: "1_r\(index)", name: "Main St Recent \(index)", regionID: 1)
        }

        store.bookmarks = bookmarkedStops.map { Bookmark(name: $0.name, regionIdentifier: 1, stop: $0) }
        store.recentStops = recentStops

        let query = makeQuery()
        let suggested = try await query.suggestedEntities()
        #expect(suggested.count == 27)

        let matched = try await query.entities(matching: "Main St")
        #expect(matched.count == StopEntityMapping.searchResultLimit)
        #expect(matched.map(\.id) == (bookmarkedStops + recentStops).prefix(20).map { "region_1_stop_\($0.id)" })
    }

    @Test func `Cross-region identifier lookup returns stored or fallback stop while suggestions stay in current region`() async throws {
        setCurrentRegion(1)
        let store = UserDefaultsStore(userDefaults: userDefaults)

        let region1Stop = makeStop(id: "1_100", name: "Seattle Stop", regionID: 1)
        let region2Stop = makeStop(id: "2_500", name: "Rynek Główny", regionID: 2)
        let region3Stop = makeStop(id: "3_600", name: "Tampa Recent", regionID: 3)

        store.bookmarks = [
            Bookmark(name: "Home", regionIdentifier: 1, stop: region1Stop),
            Bookmark(name: "Kraków", regionIdentifier: 2, stop: region2Stop),
        ]
        store.recentStops = [region3Stop]

        let query = makeQuery()
        #expect(try await query.suggestedEntities().map(\.id) == ["region_1_stop_1_100"])
        #expect(try await query.entities(matching: "Rynek").isEmpty)
        #expect(try await query.entities(matching: "Tampa").isEmpty)

        let crossRegion = try await query.entities(for: [
            "region_2_stop_2_500",
            "region_3_stop_3_600",
            "region_99_stop_99_1",
        ])
        #expect(crossRegion.map(\.regionID) == [2, 3, 99])
        #expect(crossRegion.map(\.name) == ["Rynek Główny", "Tampa Recent", nil])
        #expect(crossRegion.last?.title == "Stop 99_1")
    }
}
