//
//  StopEntityMappingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class StopEntityMappingTests: OBATestCase {

    override init() async throws {
        try await super.init()
    }

    private func makeStop(id: StopID, name: String, code: String = "", regionIdentifier: Int) -> Stop {
        Stop(id: id, name: name, code: code, location: CLLocation(latitude: 47.6097, longitude: -122.3422), regionIdentifier: regionIdentifier)
    }

    private func makeTripBookmark(stop: Stop, regionIdentifier: Int) throws -> Bookmark {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(name: "49 to Downtown", regionIdentifier: regionIdentifier, arrivalDeparture: arrivalDeparture, stop: stop)
        try #require(bookmark.isTripBookmark)
        return bookmark
    }

    /// Saved shortcuts, Spotlight and the stop activity all store this string,
    /// so its format is a contract. Change it and this fails.
    @Test func `Stop entity id is the stop activity's persistent identifier`() {
        #expect(StopEntityMapping.identifier(regionID: 1, stopID: "1_75403") == "region_1_stop_1_75403")
    }

    /// Splitting at the last `_stop_`, or reading the region as anything but
    /// a whole integer, breaks one of these.
    @Test(arguments: [
        ("region_1_stop_1_75403", AppLinksRouter.StopDestination(stopID: "1_75403", regionID: 1)),
        ("region_1500_stop_40_stop_7", AppLinksRouter.StopDestination(stopID: "40_stop_7", regionID: 1500)),
        ("foo", nil),
        ("region_x_stop_1", nil),
        ("region_1_stop_", nil),
        ("region__stop_1", nil)
    ])
    func `A stop entity id parses back to its region and stop`(identifier: String, expected: AppLinksRouter.StopDestination?) {
        let destination = StopEntityMapping.destination(fromIdentifier: identifier)
        #expect(destination == expected)

        if let destination {
            #expect(StopEntityMapping.identifier(regionID: destination.regionID, stopID: destination.stopID) == identifier)
        }
    }

    /// The recents list B before A, so putting recents ahead of bookmarks
    /// gives `[B, A]`. Dropping the dedupe repeats A or B; dropping the region
    /// filter adds the region-2 stops.
    @Test func `Suggested stops are bookmarks first, then recents, each once, that region only`() throws {
        let stopA = makeStop(id: "1_100", name: "Pine St & 3rd Ave", regionIdentifier: 1)
        let stopB = makeStop(id: "1_200", name: "Pike St & 4th Ave", regionIdentifier: 1)
        let otherRegionBookmarked = makeStop(id: "2_300", name: "Rynek Główny", regionIdentifier: 2)
        let otherRegionRecent = makeStop(id: "2_400", name: "Plac Wolności", regionIdentifier: 2)

        let bookmarks = [
            Bookmark(name: "Home", regionIdentifier: 1, stop: stopA),
            try makeTripBookmark(stop: stopA, regionIdentifier: 1),
            Bookmark(name: "Away", regionIdentifier: 2, stop: otherRegionBookmarked)
        ]
        let recentStops = [stopB, stopA, stopB, otherRegionRecent]

        let suggested = StopEntityMapping.suggested(bookmarks: bookmarks, recentStops: recentStops, regionID: 1)
        #expect(suggested.map(\.id) == ["region_1_stop_1_100", "region_1_stop_1_200"])
        #expect(suggested.map(\.name) == ["Pine St & 3rd Ave", "Pike St & 4th Ave"])

        #expect(StopEntityMapping.suggested(bookmarks: bookmarks, recentStops: recentStops, regionID: nil).isEmpty)
    }

    @Test func `Stop search matches the name or the start of the code, at most 20`() {
        let polish = StopEntityMapping.entity(for: makeStop(id: "2_1201", name: "Plac Wolności", code: "1201", regionIdentifier: 2), regionID: 2)
        let pine = StopEntityMapping.entity(for: makeStop(id: "1_75403", name: "3rd Ave & Pine St", code: "75403", regionIdentifier: 1), regionID: 1)
        let entities = [polish, pine]

        // `localizedStandardContains` ignores case and diacritics.
        #expect(StopEntityMapping.matching("wolnosci", in: entities).map(\.id) == [polish.id])
        #expect(StopEntityMapping.matching("754", in: entities).map(\.id) == [pine.id])
        #expect(StopEntityMapping.matching("403", in: entities).isEmpty)
        #expect(StopEntityMapping.matching("zzz", in: entities).isEmpty)

        let many = (1...25).map {
            StopEntityMapping.entity(for: makeStop(id: "1_\($0)", name: "Main St & \($0)th Ave", regionIdentifier: 1), regionID: 1)
        }
        let capped = StopEntityMapping.matching("Main St", in: many)
        #expect(capped.map(\.id) == many.prefix(20).map(\.id))
    }

    /// A saved shortcut can name a stop the rider has since unbookmarked, or
    /// one from another region. It must still resolve, so the app can open it
    /// or say why it can't.
    @Test func `An id nobody has stored still resolves`() {
        let fallback = StopEntityMapping.entities(forIdentifiers: ["region_1_stop_1_75403"], bookmarks: [], recentStops: [])
        #expect(fallback.count == 1)
        #expect(fallback.first?.regionID == 1)
        #expect(fallback.first?.stopID == "1_75403")
        #expect(fallback.first?.name == nil)

        let otherRegion = makeStop(id: "2_500", name: "Rynek Główny", regionIdentifier: 2)
        let recent = makeStop(id: "1_600", name: "3rd Ave & Pike St", regionIdentifier: 1)
        let resolved = StopEntityMapping.entities(
            forIdentifiers: ["region_2_stop_2_500", "foo", "region_1_stop_1_600", "region_1_stop_1_75403"],
            bookmarks: [Bookmark(name: "Kraków", regionIdentifier: 2, stop: otherRegion)],
            recentStops: [recent]
        )
        #expect(resolved.map(\.id) == ["region_2_stop_2_500", "region_1_stop_1_600", "region_1_stop_1_75403"])
        #expect(resolved.map(\.name) == ["Rynek Główny", "3rd Ave & Pike St", nil])
    }
}
