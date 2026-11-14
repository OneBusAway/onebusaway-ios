//
//  RegionStopSyncServiceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

// swiftlint:disable force_try

@Suite(.serialized)
final class RegionStopSyncServiceTests {
    private let database = try! StopCacheDatabase(inMemory: true)
    private lazy var repository = StopCacheRepository(database: database)
    private let clock = SendableBox(Date(timeIntervalSince1970: 1_790_000_000))
    private let earlier = Date(timeIntervalSince1970: 1_789_000_000)

    private func makeService(batchSize: Int = 500) -> RegionStopSyncService {
        let clock = clock
        return RegionStopSyncService(repository: repository, appVersion: "26.5", now: { clock.value }, batchSize: batchSize)
    }

    private func stop(_ id: StopID) -> Stop {
        Stop(id: id, name: "Stop \(id)", code: id, location: CLLocation(latitude: 27.95, longitude: -82.46), regionIdentifier: 1)
    }

    private func stops(_ ids: StopID...) -> Result<StopsForAgencyResult, any Error> {
        .success(.stops(ids.map(stop), etag: nil))
    }

    private func error(_ statusCode: Int, _ contentType: String) -> Result<StopsForAgencyResult, any Error> {
        let response = HTTPURLResponse(url: URL(string: "https://www.example.com")!, statusCode: statusCode, httpVersion: "2", headerFields: ["Content-Type": contentType])!
        return .failure(statusCode == 404 ? APIError.requestNotFound(response) : APIError.requestFailure(response))
    }

    private func cachedIDs(region: Int = 1) throws -> [String] {
        repository.stops(regionId: region, after: nil, limit: 10_000).stops.map(\.id)
    }

    @Test func `A complete sync writes every agency, deletes what the server dropped, and records it`() async throws {
        try repository.writeSyncedStops([stop("1_dropped")], regionId: 1, syncedAt: earlier)
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: ["1": stops("1_a", "1_b"), "2": stops("2_c")])

        let wroteStops = await makeService().sync(regionID: 1, using: fetcher)

        #expect(wroteStops)
        #expect(try cachedIDs() == ["1_a", "1_b", "2_c"])
        let state = try #require(try repository.syncState(regionId: 1))
        #expect(state.outcome == .complete)
        #expect(state.lastSuccessAt == clock.value)
        #expect(state.etag == nil)
        #expect(await fetcher.calls == ["agencies", "config", "stops 1", "stops 2"])
    }

    /// maglev answers an agency with no stops with `200 []`: still a complete sync.
    @Test func `An agency with no stops still completes`() async throws {
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: ["1": stops("1_a"), "2": stops()])

        await makeService().sync(regionID: 1, using: fetcher)

        #expect(try cachedIDs() == ["1_a"])
        #expect(try repository.syncState(regionId: 1)?.outcome == .complete)
    }

    /// Every agency answering `[]` is likelier a server problem than a region
    /// with no stops, so the stops the map cached stay.
    @Test func `Every agency answering with no stops deletes nothing`() async throws {
        try repository.writeSyncedStops([stop("1_kept")], regionId: 1, syncedAt: earlier)
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: ["1": stops(), "2": stops()])

        let wroteStops = await makeService().sync(regionID: 1, using: fetcher)

        #expect(!wroteStops)
        #expect(try cachedIDs() == ["1_kept"])
    }

    @Test func `An HTML page from the first agency records unsupported and writes nothing`() async throws {
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: ["1": error(404, "text/html;charset=utf-8"), "2": stops("2_c")])

        await makeService().sync(regionID: 1, using: fetcher)

        #expect(try cachedIDs().isEmpty)
        #expect(try repository.syncState(regionId: 1)?.outcome == .unsupported)
        #expect(await fetcher.calls == ["agencies", "config", "stops 1"])
    }

    /// A later agency failing can't mean the endpoint is missing. What arrived
    /// is kept, and nothing is deleted on partial information.
    @Test func `A later agency failing makes the sync partial and deletes nothing`() async throws {
        try repository.writeSyncedStops([stop("1_kept")], regionId: 1, syncedAt: earlier)
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: ["1": stops("1_a"), "2": error(429, "application/json")])

        let wroteStops = await makeService().sync(regionID: 1, using: fetcher)

        #expect(wroteStops)
        #expect(try cachedIDs() == ["1_a", "1_kept"])
        #expect(try repository.syncState(regionId: 1)?.outcome == .partial)
    }

    @Test func `Every agency failing records a failure that keeps the last success`() async throws {
        try repository.saveSyncState(RegionStopSyncState(regionId: 1, outcome: .complete, lastAttemptAt: earlier, lastSuccessAt: earlier, etag: nil, appVersion: "26.5"))
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": error(404, "application/json")])

        await makeService().sync(regionID: 1, using: fetcher)

        let state = try #require(try repository.syncState(regionId: 1))
        #expect(state.outcome == .failed)
        #expect(state.lastSuccessAt == earlier)
    }

    /// The request never leaves the device on Low Data Mode, and the next agency
    /// would be refused the same way, so the sync stops and retries later.
    @Test func `Low Data Mode stops the sync at the first agency`() async throws {
        let constrained = URLError(.notConnectedToInternet, userInfo: [NSURLErrorNetworkUnavailableReasonKey: URLError.NetworkUnavailableReason.constrained.rawValue])
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: ["1": .failure(constrained), "2": stops("2_c")])

        await makeService().sync(regionID: 1, using: fetcher)

        #expect(await fetcher.calls == ["agencies", "config", "stops 1"])
        #expect(try cachedIDs().isEmpty)
        #expect(try repository.syncState(regionId: 1)?.outcome == .failed)
    }

    /// Treating no agencies as a complete sync would delete every cached stop.
    @Test func `A server listing no agencies fails without deleting anything`() async throws {
        try repository.writeSyncedStops([stop("1_kept")], regionId: 1, syncedAt: earlier)
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: [], answers: [:])

        await makeService().sync(regionID: 1, using: fetcher)

        #expect(try cachedIDs() == ["1_kept"])
        #expect(try repository.syncState(regionId: 1)?.outcome == .failed)
    }

    @Test func `A maglev region with several agencies is skipped before any stops are fetched`() async throws {
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], maglev: true, answers: ["1": stops("1_a"), "2": stops("2_a")])

        await makeService().sync(regionID: 1, using: fetcher)

        #expect(try cachedIDs().isEmpty)
        #expect(try repository.syncState(regionId: 1)?.outcome == .skippedMultiAgency)
        #expect(await fetcher.calls == ["agencies", "config"])
    }

    /// The next day's check sends the stored fingerprint, and a 304 confirms the
    /// cache without writing anything.
    @Test func `A maglev region keeps its ETag and checks it the next day`() async throws {
        let first = FakeStopsForAgencyFetcher(agencyIDs: ["1"], maglev: true, answers: ["1": .success(.stops([stop("1_a")], etag: "3f9a"))])
        await makeService().sync(regionID: 1, using: first)
        let firstSync = clock.value
        #expect(try repository.syncState(regionId: 1)?.etag == "3f9a")

        clock.value = clock.value.addingTimeInterval(86_400)
        let second = FakeStopsForAgencyFetcher(agencyIDs: ["1"], maglev: true, answers: ["1": .success(.notModified)])
        let wroteStops = await makeService().sync(regionID: 1, using: second)

        #expect(!wroteStops)
        #expect(await second.calls == ["agencies", "config", "stops 1 if-none-match 3f9a"])
        let state = try #require(try repository.syncState(regionId: 1))
        #expect(state.outcome == .complete)
        #expect(state.lastAttemptAt == clock.value)
        #expect(state.lastSuccessAt == firstSync)
        #expect(try cachedIDs() == ["1_a"])
    }

    /// A 304 writes no rows, so it can't stand in for the weekly full sync: the
    /// rows would keep their first stamp until the 30-day purge deleted them.
    @Test func `Daily 304s still leave a full sync every week`() async throws {
        let first = FakeStopsForAgencyFetcher(agencyIDs: ["1"], maglev: true, answers: ["1": .success(.stops([stop("1_a")], etag: "3f9a"))])
        await makeService().sync(regionID: 1, using: first)
        let firstSync = clock.value

        for _ in 1...6 {
            clock.value = clock.value.addingTimeInterval(86_400)
            let daily = FakeStopsForAgencyFetcher(agencyIDs: ["1"], maglev: true, answers: ["1": .success(.notModified)])
            await makeService().sync(regionID: 1, using: daily)
            #expect(await daily.calls.last == "stops 1 if-none-match 3f9a")
        }

        clock.value = clock.value.addingTimeInterval(86_400)
        let weekly = FakeStopsForAgencyFetcher(agencyIDs: ["1"], maglev: true, answers: ["1": .success(.stops([stop("1_a")], etag: "3f9a"))])
        await makeService().sync(regionID: 1, using: weekly)

        #expect(await weekly.calls == ["agencies", "config", "stops 1"])
        // Restamped, so the purge 31 days after the first sync keeps it.
        repository.deleteStopsOlderThan(firstSync.addingTimeInterval(86_400), regionId: 1)
        #expect(try cachedIDs() == ["1_a"])
    }

    @Test func `A region that isn't due makes no request`() async throws {
        let yesterday = clock.value.addingTimeInterval(-86_400)
        try repository.saveSyncState(RegionStopSyncState(regionId: 1, outcome: .complete, lastAttemptAt: yesterday, lastSuccessAt: yesterday, etag: nil, appVersion: "26.5"))
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": stops("1_a")])

        let wroteStops = await makeService().sync(regionID: 1, using: fetcher)

        #expect(!wroteStops)
        #expect(await fetcher.calls.isEmpty)
    }

    @Test func `A large agency is written in batches`() async throws {
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": stops("1_1", "1_2", "1_3", "1_4", "1_5")])

        await makeService(batchSize: 2).sync(regionID: 1, using: fetcher)

        #expect(try cachedIDs() == ["1_1", "1_2", "1_3", "1_4", "1_5"])
        #expect(try repository.syncState(regionId: 1)?.outcome == .complete)
    }

    /// The second agency's answer arrives after the sync was cancelled, as after
    /// a region switch: the fetched first agency is not visible because the
    /// complete sync has not committed yet.
    @Test(.timeLimit(.minutes(1))) func `A cancelled sync writes nothing more and records nothing`() async throws {
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: ["1": stops("1_a"), "2": stops("2_late")])
        await fetcher.hold(agency: "2")
        let service = makeService()
        let sync = Task { await service.sync(regionID: 1, using: fetcher) }

        await fetcher.waitUntilHolding()
        sync.cancel()
        await fetcher.release()

        #expect(await !sync.value)
        #expect(try cachedIDs().isEmpty)
        #expect(try repository.syncState(regionId: 1) == nil)
    }

    @Test func `A retry after cancellation commits each duplicate stop once`() async throws {
        let firstFetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: [
            "1": stops("1_a", "1_duplicate"),
            "2": stops("1_duplicate", "2_b")
        ])
        await firstFetcher.hold(agency: "2")
        let service = makeService(batchSize: 1)
        let cancelledSync = Task { await service.sync(regionID: 1, using: firstFetcher) }

        await firstFetcher.waitUntilHolding()
        cancelledSync.cancel()
        await firstFetcher.release()
        #expect(await !cancelledSync.value)
        #expect(try cachedIDs().isEmpty)

        let retryFetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: [
            "1": stops("1_a", "1_duplicate"),
            "2": stops("1_duplicate", "2_b")
        ])
        #expect(await service.sync(regionID: 1, using: retryFetcher))
        #expect(try cachedIDs() == ["1_a", "1_duplicate", "2_b"])
    }

    @Test func `A database error during a later batch cleans up earlier staged batches and preserves original rows`() async throws {
        try repository.writeSyncedStops([stop("original")], regionId: 1, syncedAt: earlier)
        #expect(try cachedIDs() == ["original"])

        try await database.dbQueue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_staged_stop_batch
                BEFORE INSERT ON cachedStopSync
                WHEN NEW.id = '1_error'
                BEGIN
                    SELECT RAISE(ABORT, 'database error during later batch');
                END
                """)
        }
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": stops("1_first", "1_error")])
        let wroteStops = await makeService(batchSize: 1).sync(regionID: 1, using: fetcher)
        try await database.dbQueue.write { db in
            try db.execute(sql: "DROP TRIGGER fail_staged_stop_batch")
        }

        #expect(!wroteStops)
        #expect(try cachedIDs() == ["original"])
        let stagedCount = try await database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cachedStopSync WHERE regionId = 1")
        }
        #expect(stagedCount == 0)
        #expect(try repository.syncState(regionId: 1)?.outcome == .failed)
    }

    @Test func `A later staged batch failure preserves the previous snapshot`() async throws {
        let initialFetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": stops("old")])
        let service = makeService(batchSize: 1)
        #expect(await service.sync(regionID: 1, using: initialFetcher))
        let initialSyncID = try #require(try repository.syncState(regionId: 1)?.publishedSyncID)
        #expect(try cachedIDs() == ["old"])

        clock.value = clock.value.addingTimeInterval(86_400 * 7)

        try await database.dbQueue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_staged_stop_insert
                BEFORE INSERT ON cachedStopSync
                WHEN NEW.id = '1_fail'
                BEGIN
                    SELECT RAISE(ABORT, 'forced staged write failure');
                END
                """)
        }
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": stops("1_good", "1_fail")])
        let wroteStops = await service.sync(regionID: 1, using: fetcher)
        try await database.dbQueue.write { db in
            try db.execute(sql: "DROP TRIGGER fail_staged_stop_insert")
        }

        #expect(!wroteStops)
        #expect(try cachedIDs() == ["old"])
        let state = try #require(try repository.syncState(regionId: 1))
        #expect(state.outcome == .failed)
        #expect(state.publishedSyncID == initialSyncID)
    }

    @Test func `A partial sync carries over staged stops from the previous published snapshot`() async throws {
        let initialFetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: [
            "1": stops("1_a"),
            "2": stops("2_b")
        ])
        let service = makeService()
        #expect(await service.sync(regionID: 1, using: initialFetcher))
        let initialSyncID = try #require(try repository.syncState(regionId: 1)?.publishedSyncID)
        #expect(try cachedIDs() == ["1_a", "2_b"])

        clock.value = clock.value.addingTimeInterval(86_400 * 7)

        let partialFetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: [
            "1": stops("1_updated"),
            "2": error(429, "application/json")
        ])
        #expect(await service.sync(regionID: 1, using: partialFetcher))
        let partialState = try #require(try repository.syncState(regionId: 1))
        #expect(partialState.outcome == .partial)
        #expect(partialState.publishedSyncID != initialSyncID)
        #expect(try cachedIDs() == ["1_a", "1_updated", "2_b"])

        let oldStagedCount = try await database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cachedStopSync WHERE syncID = ?", arguments: [initialSyncID])
        }
        #expect(oldStagedCount == 0)
    }

    @Test func `A server listing no agencies preserves existing published syncID`() async throws {
        let initialFetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": stops("1_kept")])
        let service = makeService()
        #expect(await service.sync(regionID: 1, using: initialFetcher))
        let initialSyncID = try #require(try repository.syncState(regionId: 1)?.publishedSyncID)

        clock.value = clock.value.addingTimeInterval(86_400 * 7)

        let emptyFetcher = FakeStopsForAgencyFetcher(agencyIDs: [], answers: [:])
        let wroteStops = await service.sync(regionID: 1, using: emptyFetcher)

        #expect(!wroteStops)
        #expect(try cachedIDs() == ["1_kept"])
        let state = try #require(try repository.syncState(regionId: 1))
        #expect(state.outcome == .failed)
        #expect(state.publishedSyncID == initialSyncID)
    }

    /// URLSession fails a cancelled request with URLError.cancelled rather than
    /// CancellationError. That's still a cancelled sync, not a failed agency.
    @Test(.timeLimit(.minutes(1))) func `A request URLSession cancelled records nothing`() async throws {
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: ["1": stops("1_a"), "2": stops("2_c")])
        await fetcher.hold(agency: "2", failingWith: URLError(.cancelled))
        let service = makeService()
        let sync = Task { await service.sync(regionID: 1, using: fetcher) }

        await fetcher.waitUntilHolding()
        sync.cancel()
        await fetcher.release()
        await sync.value

        #expect(try cachedIDs().isEmpty)
        #expect(try repository.syncState(regionId: 1) == nil)
    }

    /// The map saves stops while a sync runs. They're newer than the sync's
    /// start, so its sweep keeps them even though the server didn't list them.
    @Test(.timeLimit(.minutes(1))) func `Stops the map saves during a sync survive its sweep`() async throws {
        clock.value = Date()
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1", "2"], answers: ["1": stops("1_a"), "2": stops("2_c")])
        await fetcher.hold(agency: "2")
        let service = makeService()
        let sync = Task { await service.sync(regionID: 1, using: fetcher) }

        await fetcher.waitUntilHolding()
        repository.saveStops([stop("1_map")], regionId: 1)
        await fetcher.release()
        await sync.value

        #expect(try cachedIDs() == ["1_a", "1_map", "2_c"])
        #expect(try repository.syncState(regionId: 1)?.outcome == .complete)
    }
}

// swiftlint:enable force_try
