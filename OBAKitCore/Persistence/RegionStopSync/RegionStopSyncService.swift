//
//  RegionStopSyncService.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The server calls a region sync makes. `RESTAPIService` is the real one; tests
/// substitute a fake.
public protocol StopsForAgencyFetching: Sendable {
    func getAgencyIDs() async throws -> [String]
    func isMaglevServer() async throws -> Bool
    func getStopsForAgency(id: String, ifNoneMatch etag: String?) async throws -> StopsForAgencyResult
}

extension RESTAPIService: StopsForAgencyFetching {
    public nonisolated func getAgencyIDs() async throws -> [String] {
        try await getAgenciesWithCoverage().list.map(\.agencyID)
    }
}

/// Keeps a copy of every stop in a region in the stop cache, from
/// `stops-for-agency` (#1555), so the map has stops offline and the whole
/// region can be searched.
///
/// Agencies are fetched one at a time, in order. Only the first agency can
/// prove the server lacks the endpoint; a later failure makes the sync partial.
/// Only a complete sync deletes the stops the server no longer lists.
///
/// No mutable state, so `Sendable` without being an actor. Runs from a detached
/// task (see `RegionStopSyncScheduler`): decoding a large region takes about a
/// second and must stay off the main actor.
public final class RegionStopSyncService: Sendable {
    private let repository: StopCacheRepository
    private let appVersion: String
    private let now: @Sendable () -> Date
    private let batchSize: Int

    public init(repository: StopCacheRepository, appVersion: String, now: @escaping @Sendable () -> Date = { Date() }, batchSize: Int = 500) {
        self.repository = repository
        self.appVersion = appVersion
        self.now = now
        self.batchSize = batchSize
    }

    /// Syncs `regionID` through `fetcher` if `RegionStopSyncPolicy` says it's due.
    ///
    /// Cancelling the calling task stops it before its next request or batch, so
    /// after a region switch nothing more is written for the old region. A
    /// cancelled sync records nothing; the next one starts over.
    public func sync(regionID: Int, using fetcher: any StopsForAgencyFetching) async {
        let previous: RegionStopSyncState?
        do {
            previous = try repository.syncState(regionId: regionID)
        } catch {
            Logger.error("Region stop sync: couldn't read the sync state of region \(regionID): \(error)")
            return
        }

        let etag: String?
        switch RegionStopSyncPolicy.decision(for: previous, now: now(), appVersion: appVersion) {
        case .skip:
            return
        case .full:
            etag = nil
        case .conditional(let previousETag):
            etag = previousETag
        }

        let start = now()
        do {
            try await run(regionID: regionID, fetcher: fetcher, start: start, etag: etag, previous: previous)
        } catch is CancellationError {
            return
        } catch {
            // URLSession reports a cancelled request as URLError.cancelled, not
            // CancellationError; either way a cancelled sync records nothing.
            if Task.isCancelled { return }
            Logger.error("Region stop sync of region \(regionID) failed: \(error)")
            record(.failed, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag)
        }
    }

    private func run(regionID: Int, fetcher: any StopsForAgencyFetching, start: Date, etag: String?, previous: RegionStopSyncState?) async throws {
        let agencyIDs = try await fetcher.getAgencyIDs()
        try Task.checkCancellation()
        guard !agencyIDs.isEmpty else {
            Logger.warn("Region stop sync: region \(regionID)'s server lists no agencies.")
            record(.failed, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag)
            return
        }

        let isMaglev = try await fetcher.isMaglevServer()
        try Task.checkCancellation()
        if isMaglev && agencyIDs.count > 1 {
            // maglev lists a stop shared by two agencies under each of them with a
            // different ID, and the map would show both. The issue's interim answer
            // is to skip such regions; every live multi-agency region runs Java.
            Logger.info("Region stop sync: skipping region \(regionID), a maglev server with \(agencyIDs.count) agencies.")
            record(.skippedMultiAgency, regionID: regionID, at: start, lastSuccessAt: nil, etag: nil)
            return
        }

        guard case let .finished(failedAgencies, newETag, wroteAny) = try await fetchAgencies(
            agencyIDs, regionID: regionID, fetcher: fetcher, start: start, etag: etag, isMaglev: isMaglev
        ) else { return }

        // A request cancelled mid-flight arrives as an agency failure.
        try Task.checkCancellation()

        if failedAgencies == agencyIDs.count {
            record(.failed, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag)
        } else if failedAgencies > 0 {
            record(.partial, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag)
        } else {
            // Every agency empty is more likely a server problem than a region with
            // no stops, so it doesn't empty the stops the map already cached.
            if wroteAny {
                try repository.deleteStops(regionId: regionID, notWrittenSince: start)
            }
            record(.complete, regionID: regionID, at: start, lastSuccessAt: start, etag: newETag)
        }
    }

    /// How fetching every agency ended: with an outcome already recorded (no
    /// endpoint, or nothing changed), or with what's left for `run` to record.
    private enum AgencyPass {
        case recorded
        case finished(failedAgencies: Int, newETag: String?, wroteAny: Bool)
    }

    /// Fetches and writes each agency in order. Only the first agency can prove
    /// the endpoint is missing; a later failure is counted and the rest go on.
    private func fetchAgencies(
        _ agencyIDs: [String],
        regionID: Int,
        fetcher: any StopsForAgencyFetching,
        start: Date,
        etag: String?,
        isMaglev: Bool
    ) async throws -> AgencyPass {
        var failedAgencies = 0
        var newETag: String?
        var writtenIDs = Set<StopID>()
        for (index, agencyID) in agencyIDs.enumerated() {
            try Task.checkCancellation()
            let result: StopsForAgencyResult
            do {
                result = try await fetcher.getStopsForAgency(id: agencyID, ifNoneMatch: index == 0 ? etag : nil)
            } catch let error as APIError where index == 0 && error.meansStopsForAgencyUnsupported {
                Logger.info("Region stop sync: region \(regionID)'s server has no stops-for-agency.")
                record(.unsupported, regionID: regionID, at: start, lastSuccessAt: nil, etag: nil)
                return .recorded
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.warn("Region stop sync: agency \(agencyID) of region \(regionID) failed: \(error)")
                failedAgencies += 1
                continue
            }

            switch result {
            case .notModified:
                // maglev's ETag fingerprints the whole feed: nothing in the region changed.
                record(.complete, regionID: regionID, at: start, lastSuccessAt: start, etag: etag)
                return .recorded
            case .stops(let stops, let responseETag):
                if index == 0 && isMaglev {
                    newETag = responseETag
                }
                // Java never lists a stop under two agencies, but a duplicate would
                // only cost a second write; skip it anyway.
                let fresh = stops.filter { writtenIDs.insert($0.id).inserted }
                try write(fresh, regionID: regionID, syncedAt: start)
            }
        }

        return .finished(failedAgencies: failedAgencies, newETag: newETag, wroteAny: !writtenIDs.isEmpty)
    }

    /// Writes in batches, so each hold on the database is short and a cancelled
    /// sync stops between batches.
    private func write(_ stops: [Stop], regionID: Int, syncedAt: Date) throws {
        var index = 0
        while index < stops.count {
            try Task.checkCancellation()
            let end = min(index + batchSize, stops.count)
            try repository.writeSyncedStops(Array(stops[index..<end]), regionId: regionID, syncedAt: syncedAt)
            index = end
        }
    }

    private func record(_ outcome: RegionStopSyncState.Outcome, regionID: Int, at attempt: Date, lastSuccessAt: Date?, etag: String?) {
        let state = RegionStopSyncState(regionId: regionID, outcome: outcome, lastAttemptAt: attempt, lastSuccessAt: lastSuccessAt, etag: etag, appVersion: appVersion)
        do {
            try repository.saveSyncState(state)
        } catch {
            Logger.error("Region stop sync: couldn't record \(outcome) for region \(regionID): \(error)")
        }
    }
}
