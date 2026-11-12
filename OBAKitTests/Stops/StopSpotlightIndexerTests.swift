//
//  StopSpotlightIndexerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import CoreSpotlight
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

    // MARK: - Launch helpers

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    /// Every indexer in a test shares the suite's `userDefaults`, so a new one
    /// sees what an earlier one remembered, as the next launch would.
    private func makeIndexer(_ index: FakeStopIndex, store: UserDataStore, cache: StopCacheRepository? = nil, region: Region, now: Date) -> StopSpotlightIndexer {
        StopSpotlightIndexer(index: index, userDataStore: store, stopCache: cache, userDefaults: userDefaults, currentRegion: { region }, isIndexingAvailable: { true }, now: { now })
    }

    /// Runs a replace of `region` to the end at `date`, as an earlier launch,
    /// region change or sync would have.
    private func finishReplace(of region: Region, store: UserDataStore, at date: Date) async {
        let indexer = makeIndexer(FakeStopIndex(), store: store, region: region, now: date)
        indexer.replaceAll()
        _ = await indexer.currentRun?.result
        // The run records itself through a weak reference to the indexer.
        withExtendedLifetime(indexer) {}
    }

    /// Launches a new indexer at `date` and returns what it did to the index.
    private func launch(in region: Region, store: UserDataStore, cache: StopCacheRepository? = nil, at date: Date) async -> [FakeStopIndex.Call] {
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: store, cache: cache, region: region, now: date)
        indexer.indexOrReplace()
        _ = await indexer.currentRun?.result
        withExtendedLifetime(indexer) {}
        return await index.log
    }

    @Test func `Replace clears, then indexes bookmarked, recent and cached stops, each once`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let stopC = makeStop("1_c", in: puget)
        let store = makeStore(bookmarked: [stopA], recent: [stopB, stopA], region: puget)
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: try makeCache([stopA, stopB, stopC], region: puget), userDefaults: userDefaults, currentRegion: { self.puget }, isIndexingAvailable: { true })

        indexer.replaceAll()
        _ = await indexer.currentRun?.result

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
        let indexer = StopSpotlightIndexer(index: index, userDataStore: makeStore(region: puget), stopCache: try makeCache(ids.map { makeStop($0, in: puget) }, region: puget), userDefaults: userDefaults, currentRegion: { self.puget }, isIndexingAvailable: { true }, batchSize: 2)

        indexer.replaceAll()
        _ = await indexer.currentRun?.result

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
        let indexer = StopSpotlightIndexer(index: index, userDataStore: makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget), stopCache: nil, userDefaults: userDefaults, currentRegion: { region }, isIndexingAvailable: { available })

        indexer.replaceAll()
        #expect(indexer.currentRun == nil)

        region = puget
        available = false
        indexer.replaceAll()
        #expect(indexer.currentRun == nil)

        available = true
        indexer.replaceAll()
        _ = await indexer.currentRun?.result
        #expect(await index.log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])
    }

    /// Indexing on top of a failed clear would mix the old entries with the new.
    @Test func `A failed clear indexes nothing`() async {
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget), stopCache: nil, userDefaults: userDefaults, currentRegion: { self.puget }, isIndexingAvailable: { true })

        indexer.replaceAll()
        _ = await indexer.currentRun?.result
        #expect(await index.log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])

        await index.failNextDelete()
        indexer.replaceAll()
        _ = await indexer.currentRun?.result
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
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, userDefaults: userDefaults, currentRegion: { region }, isIndexingAvailable: { true })

        await index.hold(next: .index)
        indexer.replaceAll()
        await index.waitUntilHolding()

        region = tampa
        indexer.replaceAll()
        await index.release()
        _ = await indexer.currentRun?.result

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
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, userDefaults: userDefaults, currentRegion: { region }, isIndexingAvailable: { true })

        await index.hold(next: .deleteAll)
        indexer.replaceAll()
        await index.waitUntilHolding()

        region = tampa
        indexer.replaceAll()
        indexer.replaceAll()
        await index.release()
        _ = await indexer.currentRun?.result

        #expect(await index.log == [
            .deleteAll,
            .deleteAll,
            .index([entityID("2_t", in: tampa)], priority: 3)
        ])
    }

    @Test func `A bookmark change upserts the bookmarked stops without clearing`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, userDefaults: userDefaults, currentRegion: { self.puget }, isIndexingAvailable: { true })

        let stopB = makeStop("1_b", in: puget)
        store.add(Bookmark(name: stopB.name, regionIdentifier: puget.regionIdentifier, stop: stopB))
        await poll(until: { indexer.currentRun != nil }, timeout: .seconds(30), "The bookmark change never reached the indexer")
        _ = await indexer.currentRun?.result

        #expect(await index.log == [.index([entityID("1_a", in: puget), entityID("1_b", in: puget)], priority: 3)])
    }

    /// Without the drop, both stops would keep priority 3 until the next replace.
    @Test func `A removed bookmark's stop drops to the recent or cached tier`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let stopC = makeStop("1_c", in: puget)
        let store = makeStore(bookmarked: [stopA, stopB, stopC], recent: [stopB], region: puget)
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, userDefaults: userDefaults, currentRegion: { self.puget }, isIndexingAvailable: { true })
        indexer.replaceAll()
        _ = await indexer.currentRun?.result

        for stop in [stopA, stopB] {
            let previousRun = indexer.currentRun
            store.delete(bookmark: try #require(store.bookmarks.first { $0.stop.id == stop.id }))
            await poll(until: { indexer.currentRun != previousRun }, timeout: .seconds(30), "The bookmark change never reached the indexer")
            _ = await indexer.currentRun?.result
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

    /// Visiting a stop stores a newer copy of it, in the recent stops and in its
    /// bookmark, without posting `.bookmarksDidChange`. So the indexer still
    /// holds the copy it indexed, and Spotlight should get the recent one.
    ///
    /// Calls `indexBookmarks()` itself rather than waiting for the
    /// `.bookmarksDidChange` the delete posts. That notification's run comes
    /// after this one and finds no bookmark left to drop, so it indexes nothing.
    @Test func `A removed bookmark's stop is indexed from its newer recent copy`() async throws {
        let indexedCopy = Stop(id: "1_a", name: "Pine St & 3rd Ave", code: "111", location: CLLocation(latitude: 47.6, longitude: -122.3), regionIdentifier: puget.regionIdentifier)
        let visitedCopy = Stop(id: "1_a", name: "3rd Ave & Pine St", code: "222", location: CLLocation(latitude: 47.6, longitude: -122.3), regionIdentifier: puget.regionIdentifier)
        let store = makeStore(bookmarked: [indexedCopy], region: puget)
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, userDefaults: userDefaults, currentRegion: { self.puget }, isIndexingAvailable: { true })
        indexer.replaceAll()
        _ = await indexer.currentRun?.result

        store.addRecentStop(visitedCopy, region: puget)
        store.delete(bookmark: try #require(store.bookmarks.first))
        indexer.indexBookmarks()
        _ = await indexer.currentRun?.result

        let demoted = try #require(await index.indexed.last { $0.priority == 2 }?.entities)
        #expect(demoted.map(\.id) == [entityID("1_a", in: puget)])
        #expect(demoted.first?.name == "3rd Ave & Pine St")
        #expect(demoted.first?.code == "222")
    }

    /// The replace took its snapshot before B was bookmarked. Run beside it,
    /// the upsert would land before the replace's delete and B would be lost.
    @Test(.timeLimit(.minutes(1))) func `A bookmark change during a replace runs after it`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)
        let index = FakeStopIndex()
        let indexer = StopSpotlightIndexer(index: index, userDataStore: store, stopCache: nil, userDefaults: userDefaults, currentRegion: { self.puget }, isIndexingAvailable: { true })

        await index.hold(next: .deleteAll)
        indexer.replaceAll()
        let replace = indexer.currentRun
        await index.waitUntilHolding()

        let stopB = makeStop("1_b", in: puget)
        store.add(Bookmark(name: stopB.name, regionIdentifier: puget.regionIdentifier, stop: stopB))
        await poll(until: { indexer.currentRun != replace }, timeout: .seconds(30), "The bookmark change never reached the indexer")
        await index.release()
        _ = await indexer.currentRun?.result

        #expect(await index.log == [
            .deleteAll,
            .index([entityID("1_a", in: puget)], priority: 3),
            .index([entityID("1_a", in: puget), entityID("1_b", in: puget)], priority: 3)
        ])
    }

    // MARK: - Launch

    @Test func `A relaunch in the region last replaced keeps Spotlight full`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let stopC = makeStop("1_c", in: puget)
        let store = makeStore(bookmarked: [stopA], recent: [stopB, stopA], region: puget)
        await finishReplace(of: puget, store: store, at: start)

        let log = await launch(in: puget, store: store, cache: try makeCache([stopA, stopB, stopC], region: puget), at: start.addingTimeInterval(day))

        #expect(log == [
            .index([entityID("1_a", in: puget)], priority: 3),
            .index([entityID("1_b", in: puget)], priority: 2),
            .index([entityID("1_c", in: puget)], priority: 1)
        ])
    }

    @Test func `A first launch, with no replace remembered, clears first`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)

        let log = await launch(in: puget, store: store, at: start)

        #expect(log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])
    }

    /// The other region's stops are still in Spotlight, so indexing on top
    /// would mix the two.
    @Test func `A launch in another region than the last replace clears first`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)
        await finishReplace(of: tampa, store: store, at: start)

        let log = await launch(in: puget, store: store, at: start.addingTimeInterval(day))

        #expect(log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])
    }

    /// The failed replace comes after one that finished, so only forgetting the
    /// last replace when a new one starts makes the next launch clear.
    @Test func `A launch after a failed clear clears again`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)
        await finishReplace(of: puget, store: store, at: start)

        let failing = FakeStopIndex()
        await failing.failNextDelete()
        let indexer = makeIndexer(failing, store: store, region: puget, now: start.addingTimeInterval(3_600))
        indexer.replaceAll()
        _ = await indexer.currentRun?.result
        #expect(await failing.log == [.deleteAllFailed])

        let log = await launch(in: puget, store: store, at: start.addingTimeInterval(2 * 3_600))

        #expect(log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])
    }

    /// The first replace is held at its last batch while a second one, which
    /// fails, cancels it. Released, the first finishes its work, but it was
    /// cancelled, so it must not record itself over the second one's start.
    @Test(.timeLimit(.minutes(1))) func `A replace cancelled at its last batch is redone on the next launch`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: store, region: puget, now: start)

        await index.hold(next: .index)
        indexer.replaceAll()
        await index.waitUntilHolding()
        await index.failNextDelete()
        indexer.replaceAll()
        await index.release()
        _ = await indexer.currentRun?.result
        // Released early, the indexer would skip the record through its weak
        // reference, and this test would pass without the cancellation check.
        withExtendedLifetime(indexer) {}
        #expect(await index.log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3), .deleteAllFailed])

        let log = await launch(in: puget, store: store, at: start.addingTimeInterval(day))

        #expect(log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])
    }

    /// Both sides of the boundary, each after its own replace, so the first
    /// launch can't affect the second.
    @Test func `A launch a week after the last replace clears first`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)

        await finishReplace(of: puget, store: store, at: start)
        let justUnderAWeek = await launch(in: puget, store: store, at: start.addingTimeInterval(7 * day - 1))
        #expect(justUnderAWeek == [.index([entityID("1_a", in: puget)], priority: 3)])

        await finishReplace(of: puget, store: store, at: start)
        let aWeek = await launch(in: puget, store: store, at: start.addingTimeInterval(7 * day))
        #expect(aWeek == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])
    }

    /// Only a replace removes stale stops, so a launch that kept the index
    /// mustn't push the next replace back.
    @Test func `A launch that keeps the index doesn't restart the week`() async {
        let store = makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget)
        await finishReplace(of: puget, store: store, at: start)

        let midweek = await launch(in: puget, store: store, at: start.addingTimeInterval(3 * day))
        #expect(midweek == [.index([entityID("1_a", in: puget)], priority: 3)])

        let log = await launch(in: puget, store: store, at: start.addingTimeInterval(7 * day))

        #expect(log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3)])
    }

    // MARK: - Re-index requests (iOS 27)

    /// D is cached but not asked for, and E is bookmarked but not asked for.
    /// Tampa's 1_d, a stop that left the app, and an id that doesn't parse are
    /// all skipped.
    @Test func `Re-indexing some stops indexes each one asked for at its tier, without clearing`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let stopC = makeStop("1_c", in: puget)
        let stopD = makeStop("1_d", in: puget)
        let stopE = makeStop("1_e", in: puget)
        let store = makeStore(bookmarked: [stopA, stopE], recent: [stopB], region: puget)
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: store, cache: try makeCache([stopA, stopB, stopC, stopD, stopE], region: puget), region: puget, now: start)

        try await indexer.reindex(.stops([
            entityID("1_a", in: puget),
            entityID("1_b", in: puget),
            entityID("1_c", in: puget),
            entityID("1_d", in: tampa),
            entityID("1_gone", in: puget),
            "not_a_stop"
        ]))

        #expect(await index.log == [
            .index([entityID("1_a", in: puget)], priority: 3),
            .index([entityID("1_b", in: puget)], priority: 2),
            .index([entityID("1_c", in: puget)], priority: 1)
        ])
    }

    @Test func `Re-indexing every stop replaces`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: makeStore(bookmarked: [stopA], region: puget), cache: try makeCache([stopA, stopB], region: puget), region: puget, now: start)

        try await indexer.reindex(.all)

        #expect(await index.log == [
            .deleteAll,
            .index([entityID("1_a", in: puget)], priority: 3),
            .index([entityID("1_b", in: puget)], priority: 1)
        ])
    }

    /// #1684 on a Spotlight launch: the request's replace forgets the last
    /// one, so the region sync finishing meanwhile replaces again, cancelling
    /// it. That replace clears the index again, so the request must not return
    /// until it has refilled it.
    @Test(.timeLimit(.minutes(1))) func `Re-indexing every stop waits for a sync's replace that cancels it`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let store = makeStore(bookmarked: [stopA], region: puget)
        await finishReplace(of: puget, store: store, at: start)
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: store, cache: try makeCache([stopA, stopB], region: puget), region: puget, now: start.addingTimeInterval(day))

        await index.hold(next: .index)
        let request = Task {
            try await indexer.reindex(.all)
            return await index.log
        }
        await index.waitUntilHolding()
        indexer.indexOrReplace()
        await index.release()
        let logWhenRequestReturned = try await request.value

        #expect(logWhenRequestReturned == [
            .deleteAll,
            .index([entityID("1_a", in: puget)], priority: 3),
            .deleteAll,
            .index([entityID("1_a", in: puget)], priority: 3),
            .index([entityID("1_b", in: puget)], priority: 1)
        ])
    }

    /// The request's replace is held at its last batch while a second replace
    /// cancels it. Released, the first finishes its work, but the second
    /// would clear it again, and here the second fails. Only a request that
    /// waited for the second can report that.
    @Test(.timeLimit(.minutes(1))) func `Re-indexing every stop throws when the replace that cancels it fails`() async {
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget), region: puget, now: start)

        await index.hold(next: .index)
        let request = Task { try await indexer.reindex(.all) }
        await index.waitUntilHolding()
        await index.failNextDelete()
        indexer.replaceAll()
        await index.release()

        await #expect(throws: FakeStopIndex.DeleteFailed.self) { try await request.value }
        #expect(await index.log == [.deleteAll, .index([entityID("1_a", in: puget)], priority: 3), .deleteAllFailed])
    }

    /// The second replace is cancelled by a third while it waits to clear,
    /// so the request follows the third.
    @Test(.timeLimit(.minutes(1))) func `Re-indexing every stop waits through each replace that cancels the one before`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: makeStore(bookmarked: [stopA], region: puget), cache: try makeCache([stopA, stopB], region: puget), region: puget, now: start)

        await index.hold(next: .index)
        let request = Task {
            try await indexer.reindex(.all)
            return await index.log
        }
        await index.waitUntilHolding()
        indexer.replaceAll()
        await index.hold(next: .deleteAll)
        await index.release()
        await index.waitUntilHolding()
        indexer.replaceAll()
        await index.release()
        let logWhenRequestReturned = try await request.value

        #expect(logWhenRequestReturned == [
            .deleteAll,
            .index([entityID("1_a", in: puget)], priority: 3),
            .deleteAll,
            .deleteAll,
            .index([entityID("1_a", in: puget)], priority: 3),
            .index([entityID("1_b", in: puget)], priority: 1)
        ])
    }

    @Test func `Re-indexing every stop throws when the clear fails`() async {
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget), region: puget, now: start)
        await index.failNextDelete()

        await #expect(throws: FakeStopIndex.DeleteFailed.self) { try await indexer.reindex(.all) }
        #expect(await index.log == [.deleteAllFailed])
    }

    /// Nothing else re-indexes these stops, so Spotlight has to hear of it.
    @Test func `Re-indexing some stops throws when indexing them fails`() async {
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: makeStore(bookmarked: [makeStop("1_a", in: puget)], region: puget), region: puget, now: start)
        await index.failNextIndex()

        await #expect(throws: FakeStopIndex.IndexFailed.self) { try await indexer.reindex(.stops([entityID("1_a", in: puget)])) }
        #expect(await index.log == [.indexFailed([entityID("1_a", in: puget)], priority: 3)])
    }

    /// Installs `indexer` as the one Spotlight's requests reach, for `body` only.
    private func withCurrentIndexer(_ indexer: StopSpotlightIndexer?, _ body: () async throws -> Void) async rethrows {
        let previous = StopSpotlightIndexer.current
        StopSpotlightIndexer.current = indexer
        defer { StopSpotlightIndexer.current = previous }
        try await body()
    }

    /// The system keeps the app alive only until the query returns, so it must
    /// return after the replace, not when it hands the request over. The delete
    /// is held until the replace has started, so a query that returned early
    /// reads an empty log.
    @available(iOS 27.0, *)
    @Test func `Spotlight's request to re-index every stop returns once the replace has finished`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: makeStore(bookmarked: [stopA], region: puget), cache: try makeCache([stopA, stopB], region: puget), region: puget, now: start)

        try await withCurrentIndexer(indexer) {
            await index.hold(next: .deleteAll)
            let query = Task {
                try await StopEntityQuery().reindexAllEntities(indexDescription: CSSearchableIndexDescription())
                return await index.log
            }
            await index.waitUntilHolding()
            await index.release()
            let logWhenQueryReturned = try await query.value

            #expect(logWhenQueryReturned == [
                .deleteAll,
                .index([entityID("1_a", in: puget)], priority: 3),
                .index([entityID("1_b", in: puget)], priority: 1)
            ])
        }
    }

    @available(iOS 27.0, *)
    @Test func `Spotlight's request to re-index some stops returns once they are indexed`() async throws {
        let stopA = makeStop("1_a", in: puget)
        let stopB = makeStop("1_b", in: puget)
        let index = FakeStopIndex()
        let indexer = makeIndexer(index, store: makeStore(recent: [stopA], region: puget), cache: try makeCache([stopA, stopB], region: puget), region: puget, now: start)

        try await withCurrentIndexer(indexer) {
            await index.hold(next: .index)
            let query = Task {
                try await StopEntityQuery().reindexEntities(for: [entityID("1_a", in: puget), entityID("1_b", in: puget)], indexDescription: CSSearchableIndexDescription())
                return await index.log
            }
            await index.waitUntilHolding()
            await index.release()
            let logWhenQueryReturned = try await query.value

            #expect(logWhenQueryReturned == [
                .index([entityID("1_a", in: puget)], priority: 2),
                .index([entityID("1_b", in: puget)], priority: 1)
            ])
        }
    }

    /// Reporting success would tell Spotlight the stops are indexed when nothing ran.
    @available(iOS 27.0, *)
    @Test func `Spotlight's request fails before the app has started indexing stops`() async {
        await withCurrentIndexer(nil) {
            await #expect(throws: StopSpotlightIndexer.NotStarted.self) {
                try await StopEntityQuery().reindexAllEntities(indexDescription: CSSearchableIndexDescription())
            }
        }
    }
}
