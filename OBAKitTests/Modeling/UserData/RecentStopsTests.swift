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
