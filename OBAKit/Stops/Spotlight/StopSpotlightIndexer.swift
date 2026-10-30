//
//  StopSpotlightIndexer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import CoreSpotlight
import OBAKitCore

/// Writes stop entities to Spotlight and clears them. Tests substitute a fake
/// that records each call.
nonisolated protocol StopEntityIndexing: Sendable {
    func deleteAll() async throws
    func index(_ entities: [StopEntity], priority: Int) async throws
}

/// The app's named Spotlight index for stops. It stores only the index name
/// and builds a `CSSearchableIndex` per call, because that class isn't `Sendable`.
nonisolated struct SpotlightStopIndex: StopEntityIndexing {
    let name = "OBAStops"

    func deleteAll() async throws {
        try await CSSearchableIndex(name: name).deleteAppEntities(ofType: StopEntity.self)
    }

    func index(_ entities: [StopEntity], priority: Int) async throws {
        try await CSSearchableIndex(name: name).indexAppEntities(entities, priority: priority)
    }
}

/// Keeps the current region's stops in Spotlight (#1555): bookmarked stops at
/// priority 3, recent ones at 2, and every other cached stop at 1, each stop
/// once, at its highest tier. The cache holds the stops browsed on the map, or
/// the whole region where `RegionStopSyncService` has synced it. Tapping a
/// result opens the stop through `OpenStopIntent`.
///
/// `Application` creates one at launch and keeps it, so only a launched app
/// writes the index. Runs happen one at a time, off the main actor.
@MainActor
final class StopSpotlightIndexer {
    private let index: any StopEntityIndexing
    private let userDataStore: UserDataStore
    private let stopCache: StopCacheRepository?
    private let currentRegion: () -> Region?
    private let isIndexingAvailable: () -> Bool
    private let batchSize: Int

    /// The run in flight, if any. Each run waits for the one before it.
    /// Internal so tests can await it instead of polling.
    private(set) var currentRun: Task<Void, Never>?

    /// The stops the latest requested run indexes at priority 3, so a bookmark
    /// change can tell which ones lost their bookmark. Set on request, not on
    /// success, so a run that fails leaves it ahead of the index until the next
    /// replace.
    private var indexedBookmarks: [StopEntity] = []

    /// Observes `NotificationCenter.default` because that is where
    /// `UserDefaultsStore` posts `.bookmarksDidChange`. Selector-based observation
    /// is removed on dealloc.
    init(
        index: any StopEntityIndexing = SpotlightStopIndex(),
        userDataStore: UserDataStore,
        stopCache: StopCacheRepository?,
        currentRegion: @escaping () -> Region?,
        isIndexingAvailable: @escaping () -> Bool = { CSSearchableIndex.isIndexingAvailable() },
        batchSize: Int = 1_000
    ) {
        self.index = index
        self.userDataStore = userDataStore
        self.stopCache = stopCache
        self.currentRegion = currentRegion
        self.isIndexingAvailable = isIndexingAvailable
        self.batchSize = batchSize

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksDidChange),
            name: .bookmarksDidChange,
            object: nil
        )
    }

    isolated deinit {
        currentRun?.cancel()
    }

    /// Clears the index, then fills it from the current region. Runs at launch
    /// and on region change, which is how the previous region's stops leave
    /// Spotlight, and after a region sync writes stops, which is how synced
    /// stops arrive and the ones the server dropped leave.
    ///
    /// The 30-day cache purge (`CoreApplication.purgeStaleStopCache()`) runs at
    /// launch and on region change too, so this can index a stop the purge
    /// removes a moment later. That stop opens normally and is gone after the
    /// next launch.
    func replaceAll() {
        guard let snapshot = makeSnapshot() else { return }
        let index = index
        let stopCache = stopCache
        let batchSize = batchSize
        indexedBookmarks = snapshot.bookmarked

        enqueue(cancellingPrevious: true) {
            // If this fails, indexing on top of the old entries would mix regions.
            try await index.deleteAll()
            try await Self.submit(snapshot.bookmarked, priority: 3, to: index)
            try await Self.submit(snapshot.recent, priority: 2, to: index)
            if let stopCache {
                try await Self.indexCachedStops(of: snapshot, from: stopCache, into: index, batchSize: batchSize)
            }
        }
    }

    /// Re-indexes the bookmarked stops at priority 3 without clearing anything,
    /// so Spotlight is never empty partway through on this common path.
    ///
    /// Waits for the run in flight rather than racing it: a replace that took
    /// its snapshot before this bookmark existed would otherwise delete this
    /// upsert.
    ///
    /// A stop that lost its bookmark drops to the tier a replace would give it:
    /// 2 if it's recent, otherwise 1. One that isn't cached either is indexed at
    /// 1 and stays there until the next replace drops it.
    func indexBookmarks() {
        guard let snapshot = makeSnapshot() else { return }
        let index = index

        let bookmarkedIDs = Set(snapshot.bookmarked.map(\.stopID))
        let recentIDs = Set(snapshot.recent.map(\.stopID))
        let unbookmarked = indexedBookmarks.filter { !bookmarkedIDs.contains($0.stopID) }
        let nowRecent = unbookmarked.filter { recentIDs.contains($0.stopID) }
        let nowCached = unbookmarked.filter { !recentIDs.contains($0.stopID) }
        indexedBookmarks = snapshot.bookmarked

        enqueue(cancellingPrevious: false) {
            try await Self.submit(snapshot.bookmarked, priority: 3, to: index)
            try await Self.submit(nowRecent, priority: 2, to: index)
            try await Self.submit(nowCached, priority: 1, to: index)
        }
    }

    // MARK: - Private

    /// The main-actor reads a run needs, taken when it is requested.
    nonisolated private struct Snapshot: Sendable {
        let regionID: Int
        let bookmarked: [StopEntity]
        let recent: [StopEntity]
    }

    private func makeSnapshot() -> Snapshot? {
        guard isIndexingAvailable() else {
            Logger.info("Spotlight indexing is unavailable on this device; not indexing stops.")
            return nil
        }
        // No region yet, as on a first launch: `regionsService(_:updatedRegion:)`
        // calls `replaceAll()` once one is chosen.
        guard let region = currentRegion() else { return nil }

        let tiers = StopEntityMapping.tiers(
            bookmarks: userDataStore.findBookmarks(in: region),
            recentStops: userDataStore.recentStops(in: region),
            regionID: region.regionIdentifier
        )
        return Snapshot(regionID: region.regionIdentifier, bookmarked: tiers.bookmarked, recent: tiers.recent)
    }

    /// Runs `work` after the run in flight finishes. `replaceAll()` cancels that
    /// run first, so a region switch stops the old region's indexing, and still
    /// waits for it, so none of its batches lands after the new region's delete.
    private func enqueue(cancellingPrevious: Bool, _ work: @escaping @Sendable () async throws -> Void) {
        let previous = currentRun
        if cancellingPrevious {
            previous?.cancel()
        }

        currentRun = Task.detached(priority: .utility) {
            // Cancelling this run cancels the one it is waiting for, too.
            await withTaskCancellationHandler {
                await previous?.value
            } onCancel: {
                previous?.cancel()
            }

            do {
                try Task.checkCancellation()
                try await work()
            } catch is CancellationError {
                return
            } catch {
                Logger.error("Failed to update the Spotlight stop index: \(error)")
            }
        }
    }

    nonisolated private static func submit(_ entities: [StopEntity], priority: Int, to index: any StopEntityIndexing) async throws {
        guard !entities.isEmpty else { return }
        try Task.checkCancellation()
        try await index.index(entities, priority: priority)
    }

    /// Pages through the region's cached stops, skipping any already indexed at
    /// a higher priority, and checks for cancellation between pages.
    nonisolated private static func indexCachedStops(
        of snapshot: Snapshot,
        from stopCache: StopCacheRepository,
        into index: any StopEntityIndexing,
        batchSize: Int
    ) async throws {
        let indexedIDs = Set((snapshot.bookmarked + snapshot.recent).map(\.stopID))
        var cursor: StopID?
        repeat {
            try Task.checkCancellation()
            let page = stopCache.stops(regionId: snapshot.regionID, after: cursor, limit: batchSize)
            let entities = page.stops
                .filter { !indexedIDs.contains($0.id) }
                .map { StopEntityMapping.entity(for: $0, regionID: snapshot.regionID) }
            try await Self.submit(entities, priority: 1, to: index)
            cursor = page.cursor
        } while cursor != nil
    }

    /// `.bookmarksDidChange` may be posted off the main actor, so hop rather than
    /// assuming the poster's isolation, as `BookmarkWidgetRefresher` does.
    @objc private nonisolated func bookmarksDidChange() {
        Task { @MainActor [weak self] in
            self?.indexBookmarks()
        }
    }
}
