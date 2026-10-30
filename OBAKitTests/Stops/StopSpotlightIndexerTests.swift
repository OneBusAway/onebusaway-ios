//
//  StopSpotlightIndexerTests.swift
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
final class StopSpotlightIndexerTests: OBATestCase {

    private let puget = Fixtures.pugetSoundRegion
    private let tampa = Fixtures.tampaRegion

    private func makeStop(_ id: StopID, in region: Region) -> Stop {
        Stop(id: id, name: "Stop \(id)", code: id, location: CLLocation(latitude: 47.6, longitude: -122.3), regionIdentifier: region.regionIdentifier)
    }

    private func entityID(_ stopID: StopID, in region: Region) -> String {
        StopEntityMapping.identifier(regionID: region.regionIdentifier, stopID: stopID)
    }

    /// The store is filled before the indexer exists, because adding a
    /// bookmark posts `.bookmarksDidChange`, which the indexer answers.
    private func makeStore(bookmarked: [Stop] = [], recent: [Stop] = [], region: Region) -> UserDefaultsStore {
        let store = UserDefaultsStore(userDefaults: userDefaults)
        for stop in bookmarked {
            store.add(Bookmark(name: stop.name, regionIdentifier: region.regionIdentifier, stop: stop))
        }
        // `addRecentStop` puts each stop first, so add in reverse to keep this order.
        for stop in recent.reversed() {
            store.addRecentStop(stop, region: region)
        }
        return store
    }

    private func makeCache(_ stops: [Stop], region: Region) throws -> StopCacheRepository {
        let cache = StopCacheRepository(database: try StopCacheDatabase(inMemory: true))
        cache.saveStops(stops, regionId: region.regionIdentifier)
        return cache
    }

    @Test func `Replace clears, then indexes bookmarked, recent and cached stops, each once`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let stopC = makeStop("1_c", in: puget)
        let store = makeStore(bookmarked: [stopA], recent: [stopB, stopA], region: puget)
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: try makeCache([stopA, stopB, stopC], region: puget), currentRegion: { self.puget }, isIndexingAvailable: { true })

        indexer.replaceAll()
        await indexer.currentRun?.value

        #expect(await index.log == [
            .deleteAll,
            .index([entityID("1_a", in: puget)], priority: 3),
            .index([entityID("1_b", in: puget)], priority: 2),
            .index([entityID("1_c", in: puget)], priority: 1)
        ])
    }

    @Test func `Cached stops are indexed in pages`() async throws {
        let ids = ["1_c1", "1_c2", "1_c3", "1_c4", "1_c5"]
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: makeStore(region: puget), stopCache: try makeCache(ids.map { makeStop($0, in: puget) }, region: puget), currentRegion: { self.puget }, isIndexingAvailable: { true }, batchSize: 2)

        indexer.replaceAll()
        await indexer.currentRun?.value

        #expect(await index.log == [
            .deleteAll,
            .index([entityID("1_c1", in: puget), entityID("1_c2", in: puget)], priority: 1),
            .index([entityID("1_c3", in: puget), entityID("1_c4", in: puget)], priority: 1),
            .index([entityID("1_c5", in: puget)], priority: 1)
        ])
    }

    /// The last call is the positive control: without it, an empty
    /// `replaceAll()` would pass the first two checks.
    @Test func `Nothing happens without a region or without indexing, and both together do`() async {
        var region: Region?
        var available = true
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget), stopCache: nil, currentRegion: { region }, isIndexingAvailable: { available })

        indexer.replaceAll()
        #expect(indexer.currentRun == nil)

        region = puget
        available = false
        indexer.replaceAll()
        #expect(indexer.currentRun == nil)

        available = true
        indexer.replaceAll()
        await indexer.currentRun?.value
        #expect(await index.log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])
    }

    /// Indexing on top of a failed clear would mix the old entries with the new.
    @Test func `A failed clear indexes nothing`() async {
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget), stopCache: nil, currentRegion: { self.puget }, isIndexingAvailable: { true })

        indexer.replaceAll()
        await indexer.currentRun?.value
        #expect(await index.log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])

        await index.failNextDelete()
        indexer.replaceAll()
        await indexer.currentRun?.value
        #expect(await index.log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3), .deleteAllFailed])
    }

    /// The first region's bookmark batch is held while the region changes. The
    /// new run waits for it before deleting, and the old run stops instead of
    /// going on to its recent stops.
    @Test(.timeLimit(.minutes(1))) func `A region switch mid-replace leaves only the new region`() async {
        var region = puget
        let pugetStop = makeStop("1_a", in: puget)
        let tampaStop = makeStop("2_t", in: tampa)
        let store = makeStore(bookmarked: [pugetStop], recent: [makeStop("1_r", in: puget)], region: puget)
        store.add(Bookmark(name: tampaStop.name, regionIdentifier: tampa.regionIdentifier, stop: tampaStop))
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, currentRegion: { region }, isIndexingAvailable: { true })

        await index.hold(next: .index)
        indexer.replaceAll()
        await index.waitUntilHolding()

        region = tampa
        indexer.replaceAll()
        await index.release()
        await indexer.currentRun?.value

        #expect(await index.log == [
            .deleteAll,
            .index([entityID("1_a", in: puget)], priority: 3),
            .deleteAll,
            .index([entityID("2_t", in: tampa)], priority: 3)
        ])
    }

    /// Three replaces in a row: the middle one is cancelled while it waits,
    /// and stops before its delete instead of clearing the index again.
    @Test(.timeLimit(.minutes(1))) func `Rapid region switches skip the runs they replace`() async {
        var region = puget
        let tampaStop = makeStop("2_t", in: tampa)
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)
        store.add(Bookmark(name: tampaStop.name, regionIdentifier: tampa.regionIdentifier, stop: tampaStop))
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, currentRegion: { region }, isIndexingAvailable: { true })

        await index.hold(next: .deleteAll)
        indexer.replaceAll()
        await index.waitUntilHolding()

        region = tampa
        indexer.replaceAll()
        indexer.replaceAll()
        await index.release()
        await indexer.currentRun?.value

        #expect(await index.log == [
            .deleteAll,
            .deleteAll,
            .index([entityID("2_t", in: tampa)], priority: 3)
        ])
    }

    @Test func `A bookmark change upserts the bookmarked stops without clearing`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, currentRegion: { self.puget }, isIndexingAvailable: { true })

        let stopB = makeStop("1_b", in: puget)
        store.add(Bookmark(name: stopB.name, regionIdentifier: puget.regionIdentifier, stop: stopB))
        await poll(until: { indexer.currentRun != nil }, timeout: .seconds(30), "The bookmark change never reached the indexer")
        await indexer.currentRun?.value

        #expect(await index.log == [.index([entityID("1_a", in: puget), entityID("1_b", in: puget)], priority: 3)])
    }

    /// Without the drop, both stops would keep priority 3 until the next replace.
    @Test func `A removed bookmark's stop drops to the recent or cached tier`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let stopC = makeStop("1_c", in: puget)
        let store = makeStore(bookmarked: [stopA, stopB, stopC], recent: [stopB], region: puget)
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, currentRegion: { self.puget }, isIndexingAvailable: { true })
        indexer.replaceAll()
        await indexer.currentRun?.value

        for stop in [stopA, stopB] {
            let previousRun = indexer.currentRun
            store.delete(bookmark: try #require(store.bookmarks.first { $0.stop.id == stop.id }))
            await poll(until: { indexer.currentRun != previousRun }, timeout: .seconds(30), "The bookmark change never reached the indexer")
            await indexer.currentRun?.value
        }

        #expect(await index.log == [
            .deleteAll,
            .index([entityID("1_a", in: puget), entityID("1_b", in: puget), entityID("1_c", in: puget)], priority: 3),
            .index([entityID("1_b", in: puget), entityID("1_c", in: puget)], priority: 3),
            .index([entityID("1_a", in: puget)], priority: 1),
            .index([entityID("1_c", in: puget)], priority: 3),
            .index([entityID("1_b", in: puget)], priority: 2)
        ])
    }

    /// The replace took its snapshot before B was bookmarked. Run beside it,
    /// the upsert would land before the replace's delete and B would be lost.
    @Test(.timeLimit(.minutes(1))) func `A bookmark change during a replace runs after it`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, currentRegion: { self.puget }, isIndexingAvailable: { true })

        await index.hold(next: .deleteAll)
        indexer.replaceAll()
        let replace = indexer.currentRun
        await index.waitUntilHolding()

        let stopB = makeStop("1_b", in: puget)
        store.add(Bookmark(name: stopB.name, regionIdentifier: puget.regionIdentifier, stop: stopB))
        await poll(until: { indexer.currentRun != replace }, timeout: .seconds(30), "The bookmark change never reached the indexer")
        await index.release()
        await indexer.currentRun?.value

        #expect(await index.log == [
            .deleteAll,
            .index([entityID("1_a", in: puget)], priority: 3),
            .index([entityID("1_a", in: puget), entityID("1_b", in: puget)], priority: 3)
        ])
    }
}
