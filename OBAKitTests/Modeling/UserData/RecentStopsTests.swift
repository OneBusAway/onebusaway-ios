//
//  RecentStopsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class RecentStopsTests: OBATestCase {

    /// Only stops belonging to the supplied region come back, and the store's
    /// most-recently-used ordering is preserved.
    @Test func `Recent stops in region filters by region identifier`() throws {
        let stops = try Fixtures.loadSomeStops()
        let first = try #require(stops.first)
        let second = try #require(stops.dropFirst().first)

        // Production stops receive regionIdentifier from RESTAPIResponse.loadReferences;
        // fixture stops bypass that path, so we assign it here to match production state.
        first.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        second.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier

        let store = UserDefaultsStore(userDefaults: userDefaults)
        store.addRecentStop(first, region: Fixtures.pugetSoundRegion)
        store.addRecentStop(second, region: Fixtures.pugetSoundRegion)

        let recents = store.recentStops(in: Fixtures.pugetSoundRegion)

        // addRecentStop inserts at index 0, so the newest is first.
        #expect(recents.map(\.id) == [second.id, first.id])
    }

    /// Builds a `Stop` from raw JSON so a test can vary a single field. Every
    /// field `Stop.isEqual` compares is `let` except `regionIdentifier`, so two
    /// instances that differ in, say, their route list can only be produced by
    /// decoding them separately — which is exactly what happens in production
    /// when the same stop comes back from two different API responses.
    private static func makeStop(id: String, routeIDs: [String], regionIdentifier: Int) throws -> Stop {
        let json = """
        {
            "code": "660",
            "direction": "S",
            "id": "\(id)",
            "lat": 47.6134,
            "lon": -122.3378,
            "locationType": 0,
            "name": "3rd Ave & Pike St",
            "routeIds": \(String(data: try JSONSerialization.data(withJSONObject: routeIDs), encoding: .utf8)!),
            "regionIdentifier": \(regionIdentifier)
        }
        """
        return try JSONDecoder().decode(Stop.self, from: Data(json.utf8))
    }

    /// Re-viewing a stop whose details changed server-side must replace the
    /// stored copy, not append a second one: `id` is the stop's identity, and
    /// the Recent Stops list keys its rows off it. Two rows with one `id` make
    /// SwiftUI's `ForEach` complain and render undefined results.
    @Test func `Re-adding a stop whose details changed replaces it rather than duplicating`() throws {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let region = Fixtures.pugetSoundRegion

        let original = try Self.makeStop(id: "1_660", routeIDs: ["1_100479"], regionIdentifier: region.regionIdentifier)
        // Same stop, but the agency now runs another route through it.
        let updated = try Self.makeStop(id: "1_660", routeIDs: ["1_100479", "1_102581"], regionIdentifier: region.regionIdentifier)

        store.addRecentStop(original, region: region)
        store.addRecentStop(updated, region: region)

        let recents = store.recentStops(in: region)
        #expect(recents.count == 1)
        #expect(recents.filter { $0.id == "1_660" }.count == 1)
        // The newer copy wins, so the refreshed route list is what's stored.
        #expect(recents.first?.routeIDs == ["1_100479", "1_102581"])
    }

    /// Deletion identifies the stop the same way: a swipe-to-delete passes the
    /// instance the list is rendering, which may not be field-for-field equal to
    /// the stored copy.
    @Test func `Deleting a recent stop removes it even when the stored copy differs`() throws {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let region = Fixtures.pugetSoundRegion

        let stored = try Self.makeStop(id: "1_660", routeIDs: ["1_100479"], regionIdentifier: region.regionIdentifier)
        let refreshed = try Self.makeStop(id: "1_660", routeIDs: ["1_100479", "1_102581"], regionIdentifier: region.regionIdentifier)

        store.addRecentStop(stored, region: region)
        store.delete(recentStop: refreshed)

        #expect(store.recentStops(in: region).isEmpty)
    }

    /// A store written before recents were keyed on `id` can already hold two
    /// entries for one stop. The read path collapses them, so a list keying its
    /// rows off `id` renders correctly without waiting for the user to revisit
    /// that stop.
    @Test func `Recent stops in region collapses duplicates already in the store`() throws {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        let region = Fixtures.pugetSoundRegion

        let newer = try Self.makeStop(id: "1_660", routeIDs: ["1_100479", "1_102581"], regionIdentifier: region.regionIdentifier)
        let older = try Self.makeStop(id: "1_660", routeIDs: ["1_100479"], regionIdentifier: region.regionIdentifier)
        let other = try Self.makeStop(id: "1_75403", routeIDs: ["1_100479"], regionIdentifier: region.regionIdentifier)

        // Seed the corrupted state directly — `addRecentStop` no longer produces it.
        store.recentStops = [newer, older, other]

        let recents = store.recentStops(in: region)

        #expect(recents.map(\.id) == ["1_660", "1_75403"])
        // The first (most recent) occurrence survives.
        #expect(recents.first?.routeIDs == ["1_100479", "1_102581"])
    }

    /// A nil region yields an empty list rather than every stored stop.
    @Test func `Recent stops in region returns empty for a nil region`() throws {
        let stops = try Fixtures.loadSomeStops()
        let first = try #require(stops.first)

        // Production stops receive regionIdentifier from RESTAPIResponse.loadReferences;
        // fixture stops bypass that path, so we assign it here to match production state.
        first.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier

        let store = UserDefaultsStore(userDefaults: userDefaults)
        store.addRecentStop(first, region: Fixtures.pugetSoundRegion)

        #expect(store.recentStops(in: nil).isEmpty)
    }
}
