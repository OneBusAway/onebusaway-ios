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
protocol StopsForAgencyFetching: Sendable {
    func getAgencyIDs() async throws -> [String]
    func isMaglevServer() async throws -> Bool
    func getStopsForAgency(id: String, ifNoneMatch etag: String?) async throws -> StopsForAgencyResult
}

extension RESTAPIService: StopsForAgencyFetching {
    nonisolated func getAgencyIDs() async throws -> [String] {
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
final class RegionStopSyncService: Sendable {
    private let repository: StopCacheRepository
    private let appVersion: String
    private let now: @Sendable () -> Date
    private let batchSize: Int

    init(repository: StopCacheRepository, appVersion: String, now: @escaping @Sendable () -> Date = { Date() }, batchSize: Int = 500) {
        self.repository = repository
        self.appVersion = appVersion
        self.now = now
        self.batchSize = batchSize
    }

    /// Syncs `regionID` through `fetcher` if `RegionStopSyncPolicy` says it's due.
    /// Returns whether a complete or partial sync wrote stops, so the caller can
    /// rebuild what it derives from the cache.
    ///
    /// Cancelling the calling task stops it before its next request or publication,
    /// so staged rows from an interrupted region switch remain invisible. Once the
    /// publication marker is committed, the sync completes and reports its result.
    @discardableResult
    func sync(regionID: Int, using fetcher: any StopsForAgencyFetching) async -> Bool {
        let previous: RegionStopSyncState?
        do {
            previous = try repository.syncState(regionId: regionID)
        } catch {
            Logger.error("Region stop sync: couldn't read the sync state of region \(regionID): \(error)")
            return false
        }

        let etag: String?
        switch RegionStopSyncPolicy.decision(for: previous, now: now(), appVersion: appVersion) {
        case .skip:
            return false
        case .full:
            etag = nil
        case .conditional(let previousETag):
            etag = previousETag
        }

        let start = now()
        let syncID = UUID().uuidString
        do {
            return try await run(regionID: regionID, fetcher: fetcher, start: start, etag: etag, previous: previous, syncID: syncID)
        } catch is CancellationError {
            try? repository.discardStagedStops(regionId: regionID, syncID: syncID)
            return false
        } catch {
            try? repository.discardStagedStops(regionId: regionID, syncID: syncID)
            // URLSession reports a cancelled request as URLError.cancelled, not
            // CancellationError; either way a cancelled sync records nothing.
            if Task.isCancelled { return false }
            Logger.error("Region stop sync of region \(regionID) failed: \(error)")
            record(.failed, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag, publishedSyncID: previous?.publishedSyncID)
            return false
        }
    }

    /// Returns whether it wrote stops.
    private func run(regionID: Int, fetcher: any StopsForAgencyFetching, start: Date, etag: String?, previous: RegionStopSyncState?, syncID: String) async throws -> Bool {
        let agencyIDs = try await fetcher.getAgencyIDs()
        try Task.checkCancellation()
        guard !agencyIDs.isEmpty else {
            Logger.warn("Region stop sync: region \(regionID)'s server lists no agencies.")
            record(.failed, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag, publishedSyncID: previous?.publishedSyncID)
            return false
        }

        let isMaglev = try await fetcher.isMaglevServer()
        try Task.checkCancellation()
        if isMaglev && agencyIDs.count > 1 {
            // maglev lists a stop shared by two agencies under each of them with a
            // different ID, and the map would show both. The issue's interim answer
            // is to skip such regions; every live multi-agency region runs Java.
            Logger.info("Region stop sync: skipping region \(regionID), a maglev server with \(agencyIDs.count) agencies.")
            record(.skippedMultiAgency, regionID: regionID, at: start, lastSuccessAt: nil, etag: nil, publishedSyncID: previous?.publishedSyncID)
            return false
        }

        guard case let .finished(failedAgencies, newETag, wroteAny) = try await fetchAgencies(
            agencyIDs, regionID: regionID, fetcher: fetcher, start: start, etag: etag, isMaglev: isMaglev, previous: previous, syncID: syncID
        ) else { return false }

        // Cancellation is checked before publication. Once the marker is saved,
        // the snapshot is committed and cancellation must not turn it into a
        // reported failure.
        try Task.checkCancellation()

        return try publish(
            regionID: regionID,
            start: start,
            newETag: newETag,
            previous: previous,
            syncID: syncID,
            failedAgencies: failedAgencies,
            totalAgencies: agencyIDs.count,
            wroteAny: wroteAny
        )
    }

    private func publish(
        regionID: Int,
        start: Date,
        newETag: String?,
        previous: RegionStopSyncState?,
        syncID: String,
        failedAgencies: Int,
        totalAgencies: Int,
        wroteAny: Bool
    ) throws -> Bool {
        if failedAgencies == totalAgencies {
            record(.failed, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag, publishedSyncID: previous?.publishedSyncID)
            return wroteAny
        }
        if failedAgencies > 0 {
            guard wroteAny else {
                record(.failed, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag, publishedSyncID: previous?.publishedSyncID)
                return false
            }
            if let previousSyncID = previous?.publishedSyncID {
                try repository.carryOverStagedStops(regionId: regionID, fromSyncID: previousSyncID, toSyncID: syncID)
            }
            guard record(.partial, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag, publishedSyncID: syncID) else { return false }
            cleanupAfterPublish(regionID: regionID, currentSyncID: syncID)
            return wroteAny
        }

        // Every agency empty is more likely a server problem than a region with
        // no stops, so it doesn't empty the stops the map already cached.
        if wroteAny {
            guard record(.complete, regionID: regionID, at: start, lastSuccessAt: start, etag: newETag, publishedSyncID: syncID) else { return false }
            cleanupAfterPublish(regionID: regionID, currentSyncID: syncID, staleStopsOlderThan: start)
        } else {
            guard record(.complete, regionID: regionID, at: start, lastSuccessAt: start, etag: newETag, publishedSyncID: previous?.publishedSyncID) else { return false }
        }
        return wroteAny
    }

    private func cleanupAfterPublish(regionID: Int, currentSyncID: String, staleStopsOlderThan: Date? = nil) {
        do {
            try repository.purgeSupersededStagedStops(regionId: regionID, currentSyncID: currentSyncID)
        } catch {
            Logger.error("Failed to purge superseded staged stops for region \(regionID): \(error)")
        }
        if let staleStopsOlderThan {
            do {
                try repository.deleteStops(regionId: regionID, notWrittenSince: staleStopsOlderThan)
            } catch {
                Logger.error("Failed to delete stale stops after sync for region \(regionID): \(error)")
            }
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
        isMaglev: Bool,
        previous: RegionStopSyncState?,
        syncID: String
    ) async throws -> AgencyPass {
        var failedAgencies = 0
        var newETag: String?
        var wroteAny = false
        for (index, agencyID) in agencyIDs.enumerated() {
            try Task.checkCancellation()
            let result: StopsForAgencyResult
            do {
                result = try await fetcher.getStopsForAgency(id: agencyID, ifNoneMatch: index == 0 ? etag : nil)
            } catch let error as APIError where index == 0 && error.meansStopsForAgencyUnsupported {
                Logger.info("Region stop sync: region \(regionID)'s server has no stops-for-agency.")
                record(.unsupported, regionID: regionID, at: start, lastSuccessAt: nil, etag: nil, publishedSyncID: previous?.publishedSyncID)
                return .recorded
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // URLSession reports a cancelled request as URLError.cancelled.
                if Task.isCancelled { throw CancellationError() }
                if (error as? URLError)?.networkUnavailableReason == .constrained {
                    // Low Data Mode refuses every agency alike; the retry comes later.
                    Logger.info("Region stop sync: Low Data Mode is on, so region \(regionID) waits.")
                    record(.failed, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: previous?.etag, publishedSyncID: previous?.publishedSyncID)
                    return .recorded
                }
                Logger.warn("Region stop sync: agency \(agencyID) of region \(regionID) failed: \(error)")
                failedAgencies += 1
                continue
            }

            switch result {
            case .notModified:
                // maglev's ETag fingerprints the whole feed: nothing in the region changed.
                // The rows keep the last full sync's stamp, so `lastSuccessAt` keeps it
                // too, and the weekly full sync restamps them before the 30-day purge.
                record(.complete, regionID: regionID, at: start, lastSuccessAt: previous?.lastSuccessAt, etag: etag, publishedSyncID: previous?.publishedSyncID)
                return .recorded
            case .stops(let stops, let responseETag):
                if index == 0 && isMaglev {
                    newETag = responseETag
                }
                var batchStart = 0
                while batchStart < stops.count {
                    let batchEnd = min(batchStart + batchSize, stops.count)
                    try Task.checkCancellation()
                    try repository.stageSyncedStops(Array(stops[batchStart..<batchEnd]), regionId: regionID, syncID: syncID, syncedAt: start)
                    batchStart = batchEnd
                }
                wroteAny = wroteAny || !stops.isEmpty
            }
        }

        // Fetching is cancellable; the publication marker below is the visibility
        // boundary for the whole sync. Staged batches remain invisible until it.
        try Task.checkCancellation()

        return .finished(failedAgencies: failedAgencies, newETag: newETag, wroteAny: wroteAny)
    }

    @discardableResult
    private func record(_ outcome: RegionStopSyncState.Outcome, regionID: Int, at attempt: Date, lastSuccessAt: Date?, etag: String?, publishedSyncID: String? = nil) -> Bool {
        let state = RegionStopSyncState(regionId: regionID, outcome: outcome, lastAttemptAt: attempt, lastSuccessAt: lastSuccessAt, etag: etag, appVersion: appVersion, publishedSyncID: publishedSyncID)
        do {
            try repository.saveSyncState(state)
            return true
        } catch {
            Logger.error("Region stop sync: couldn't record \(outcome) for region \(regionID): \(error)")
            return false
        }
    }
}
