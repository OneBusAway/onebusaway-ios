//
//  RegionStopSyncSchedulerTests.swift
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
final class RegionStopSyncSchedulerTests {
    private let database = try! StopCacheDatabase(inMemory: true)
    private lazy var repository = StopCacheRepository(database: database)

    private func makeScheduler(delay: Duration) -> RegionStopSyncScheduler {
        RegionStopSyncScheduler(service: RegionStopSyncService(repository: repository, appVersion: "26.5"), delay: delay)
    }

    private func answer(_ ids: StopID...) -> Result<StopsForAgencyResult, any Error> {
        .success(.stops(ids.map { Stop(id: $0, name: $0, location: CLLocation(latitude: 27.95, longitude: -82.46)) }, etag: nil))
    }

    private func cachedIDs(region: Int) throws -> [String] {
        try database.dbQueue.read { try String.fetchAll($0, sql: "SELECT id FROM cachedStop WHERE regionId = ? ORDER BY id", arguments: [region]) }
    }

    /// Launch, the first activation and a region change arrive within moments
    /// of each other. They make one sync, not three.
    @Test func `Requests in quick succession make one sync`() async throws {
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": answer("1_a")])
        let scheduler = makeScheduler(delay: .milliseconds(200))

        scheduler.schedule(regionID: 1, using: fetcher)
        scheduler.schedule(regionID: 1, using: fetcher)
        scheduler.schedule(regionID: 1, using: fetcher)
        await scheduler.pendingSync?.value

        #expect(await fetcher.calls == ["agencies", "config", "stops 1"])
        #expect(try cachedIDs(region: 1) == ["1_a"])
    }

    /// Region A's sync is mid-flight when the rider switches to B. A's late
    /// answer is never written; B's is.
    @Test(.timeLimit(.minutes(1))) func `A request for another region cancels the sync in flight`() async throws {
        let regionA = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": answer("1_late")])
        let regionB = FakeStopsForAgencyFetcher(agencyIDs: ["2"], answers: ["2": answer("2_b")])
        await regionA.hold(agency: "1")
        let scheduler = makeScheduler(delay: .zero)

        scheduler.schedule(regionID: 1, using: regionA)
        let syncA = scheduler.pendingSync
        await regionA.waitUntilHolding()

        scheduler.schedule(regionID: 2, using: regionB)
        await regionA.release()
        await syncA?.value
        await scheduler.pendingSync?.value

        #expect(try cachedIDs(region: 1).isEmpty)
        #expect(try cachedIDs(region: 2) == ["2_b"])
    }

    /// Activation fires whenever a system alert or Control Center is dismissed.
    /// Restarting a slow sync each time could keep it from ever finishing.
    @Test(.timeLimit(.minutes(1))) func `A request for the region already syncing leaves it alone`() async throws {
        let fetcher = FakeStopsForAgencyFetcher(agencyIDs: ["1"], answers: ["1": answer("1_a")])
        await fetcher.hold(agency: "1")
        let scheduler = makeScheduler(delay: .zero)

        scheduler.schedule(regionID: 1, using: fetcher)
        let sync = scheduler.pendingSync
        await fetcher.waitUntilHolding()

        scheduler.schedule(regionID: 1, using: fetcher)
        await fetcher.release()
        await sync?.value
        await scheduler.pendingSync?.value

        #expect(await fetcher.calls == ["agencies", "config", "stops 1"])
        #expect(try cachedIDs(region: 1) == ["1_a"])
    }
}

// swiftlint:enable force_try
