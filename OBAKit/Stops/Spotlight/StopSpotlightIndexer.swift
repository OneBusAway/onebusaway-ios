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
    private let userDefaults: UserDefaults
    private let currentRegion: () -> Region?
    private let isIndexingAvailable: () -> Bool
    private let now: () -> Date
    private let batchSize: Int

    /// How long a finished replace lets a launch or a region sync skip the clear.
    /// Only a replace removes the stops the 30-day cache purge or a sync drops,
    /// and otherwise only a region change would trigger one. A week
    /// matches the sync's own full interval (`RegionStopSyncPolicy.fullSyncInterval`).
    private static let replaceInterval: TimeInterval = 7 * 86_400

    private static let lastReplaceRegionKey = "StopSpotlightIndexer.lastReplaceRegionID"
    private static let lastReplaceDateKey = "StopSpotlightIndexer.lastReplaceDate"

    /// The run in flight, if any. Each run waits for the one before it.
    /// Internal so tests can await it instead of polling.
    private(set) var currentRun: Task<Void, Never>?

    /// The stops the latest requested run indexes at priority 3, so a bookmark
    /// change can tell which ones lost their bookmark. Set on request, not on
    /// success, so a run that fails leaves it ahead of the index until the next
    /// replace.
    private var indexedBookmarks: [StopEntity] = []

    /// Observes `NotificationCenter.default` because that is where
    /// `UserDefaultsStore` posts `.bookmarksDidChange` and `StopReindexRequest`
    /// posts `.stopReindexRequested`. Selector-based observation is removed on
    /// dealloc.
    ///
    /// `userDefaults` remembers the last finished replace across launches. It has
    /// no default, so a test can't write `UserDefaults.standard` by leaving it out.
    init(
        index: any StopEntityIndexing = SpotlightStopIndex(),
        userDataStore: UserDataStore,
        stopCache: StopCacheRepository?,
        userDefaults: UserDefaults,
        currentRegion: @escaping () -> Region?,
        isIndexingAvailable: @escaping () -> Bool = { CSSearchableIndex.isIndexingAvailable() },
        now: @escaping () -> Date = { Date() },
        batchSize: Int = 1_000
    ) {
        self.index = index
        self.userDataStore = userDataStore
        self.stopCache = stopCache
        self.userDefaults = userDefaults
        self.currentRegion = currentRegion
        self.isIndexingAvailable = isIndexingAvailable
        self.now = now
        self.batchSize = batchSize

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksDidChange),
            name: .bookmarksDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reindexRequested(_:)),
            name: .stopReindexRequested,
            object: nil
        )
    }

    isolated deinit {
        currentRun?.cancel()
    }

    /// Indexes the current region's stops at launch and after a region sync
    /// writes them. If a replace of this region finished within
    /// `replaceInterval`, it indexes on top of what Spotlight already holds, so
    /// the stops stay searchable while it runs. Otherwise it replaces: on the
    /// first launch, after a replace that failed or was cut short, or when the
    /// last replace was of another region.
    ///
    /// Indexing an entity whose ID is already in the index replaces it, so this
    /// updates every stop it covers. Spotlight can't list what it holds, though,
    /// so a stop that left the cache stays until the next replace.
    func indexOrReplace() {
        guard let snapshot = makeSnapshot() else { return }
        guard hasRecentReplace(of: snapshot.regionID) else {
            Logger.info("No recent Spotlight stop index for region \(snapshot.regionID); rebuilding it.")
            replace(with: snapshot)
            return
        }

        let index = index
        let stopCache = stopCache
        let batchSize = batchSize
        indexedBookmarks = snapshot.bookmarked

        enqueue(cancellingPrevious: false) {
            try await Self.fill(index, from: snapshot, stopCache: stopCache, batchSize: batchSize)
        }
    }

    /// Clears the index, then fills it from the current region. Runs on region
    /// change, which is how the previous region's stops leave Spotlight, and
    /// when `indexOrReplace()` finds no recent replace, which is how the stops a
    /// region sync dropped leave.
    ///
    /// The 30-day cache purge (`CoreApplication.purgeStaleStopCache()`) runs at
    /// launch and on region change too, so this can index a stop the purge
    /// removes a moment later. That stop opens normally and is gone after the
    /// next replace, at most `replaceInterval` later.
    func replaceAll() {
        guard let snapshot = makeSnapshot() else { return }
        replace(with: snapshot)
    }

    /// Re-indexes the bookmarked stops at priority 3 without clearing anything,
    /// so Spotlight is never empty partway through on this common path.
    ///
    /// Waits for the run in flight rather than racing it: a replace that took
    /// its snapshot before this bookmark existed would otherwise delete this
    /// upsert.
    ///
    /// A stop that lost its bookmark drops to the tier a replace would give it:
    /// 2 if it's recent, otherwise 1. A recent one is indexed from its recent
    /// copy: a visit refreshes the stop's recent copy and its bookmark's without
    /// posting `.bookmarksDidChange`, so `indexedBookmarks` can hold an older
    /// one. Any other is indexed from `indexedBookmarks`, and one that isn't
    /// cached either stays at 1 until the next replace drops it.
    func indexBookmarks() {
        guard let snapshot = makeSnapshot() else { return }
        let index = index

        let bookmarkedIDs = Set(snapshot.bookmarked.map(\.stopID))
        let recentIDs = Set(snapshot.recent.map(\.stopID))
        let unbookmarked = indexedBookmarks.filter { !bookmarkedIDs.contains($0.stopID) }
        let unbookmarkedIDs = Set(unbookmarked.map(\.stopID))
        let nowRecent = snapshot.recent.filter { unbookmarkedIDs.contains($0.stopID) }
        let nowCached = unbookmarked.filter { !recentIDs.contains($0.stopID) }
        indexedBookmarks = snapshot.bookmarked

        enqueue(cancellingPrevious: false) {
            try await Self.submit(snapshot.bookmarked, priority: 3, to: index)
            try await Self.submit(nowRecent, priority: 2, to: index)
            try await Self.submit(nowCached, priority: 1, to: index)
        }
    }

    /// Answers Spotlight asking for stops again, which `StopEntityQuery` passes
    /// on from iOS 27.
    ///
    /// `.all` replaces: Spotlight has likely lost its copy, and a replace also
    /// restarts `replaceInterval`.
    ///
    /// `.stops` indexes only those stops, each at the tier a replace would give
    /// it, without clearing. A stop from another region, or one the app no
    /// longer has, is skipped, which leaves it out of Spotlight as a replace
    /// would. The cache has no lookup by id, so this pages through the region's
    /// cached stops as a replace does.
    func reindex(_ scope: StopReindexRequest.Scope) {
        switch scope {
        case .all:
            replaceAll()
        case .stops(let identifiers):
            reindexStops(identifiers)
        }
    }

    // MARK: - Private

    private func reindexStops(_ identifiers: [StopEntity.ID]) {
        guard let snapshot = makeSnapshot() else { return }
        let destinations = identifiers.compactMap(StopEntityMapping.destination(fromIdentifier:))
        let inRegion = destinations.filter { $0.regionID == snapshot.regionID }
        if inRegion.count < identifiers.count {
            Logger.info("Spotlight asked to re-index \(identifiers.count) stops; \(identifiers.count - destinations.count) ids don't name a stop and \(destinations.count - inRegion.count) are outside region \(snapshot.regionID). Skipping those.")
        }
        guard !inRegion.isEmpty else { return }
        let wanted = Set(inRegion.map(\.stopID))

        let index = index
        let stopCache = stopCache
        let batchSize = batchSize

        enqueue(cancellingPrevious: false) {
            try await Self.submit(snapshot.bookmarked.filter { wanted.contains($0.stopID) }, priority: 3, to: index)
            try await Self.submit(snapshot.recent.filter { wanted.contains($0.stopID) }, priority: 2, to: index)
            if let stopCache {
                try await Self.indexCachedStops(of: snapshot, from: stopCache, into: index, batchSize: batchSize, only: wanted)
            }
        }
    }

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

    /// Forgets the last replace before clearing, and remembers this one only
    /// once it finishes, so a launch after one that failed, was cancelled or was
    /// killed with the app replaces again instead of indexing on top.
    private func replace(with snapshot: Snapshot) {
        let index = index
        let stopCache = stopCache
        let batchSize = batchSize
        indexedBookmarks = snapshot.bookmarked
        forgetLastReplace()

        enqueue(cancellingPrevious: true) { [weak self] in
            // If this fails, indexing on top of the old entries would mix regions.
            try await index.deleteAll()
            try await Self.fill(index, from: snapshot, stopCache: stopCache, batchSize: batchSize)
            await self?.rememberReplace(of: snapshot.regionID)
        }
    }

    private func hasRecentReplace(of regionID: Int) -> Bool {
        guard userDefaults.object(forKey: Self.lastReplaceRegionKey) as? Int == regionID,
              let replacedAt = userDefaults.object(forKey: Self.lastReplaceDateKey) as? Date else {
            return false
        }
        return now().timeIntervalSince(replacedAt) < Self.replaceInterval
    }

    private func forgetLastReplace() {
        userDefaults.removeObject(forKey: Self.lastReplaceRegionKey)
        userDefaults.removeObject(forKey: Self.lastReplaceDateKey)
    }

    /// Called by the run itself once it has filled the index. The cancellation
    /// check is on the main actor, where `replace(with:)` cancels, so a run that
    /// a newer replace cancelled can't record itself after that replace forgot it.
    private func rememberReplace(of regionID: Int) {
        guard !Task.isCancelled else { return }
        userDefaults.set(regionID, forKey: Self.lastReplaceRegionKey)
        userDefaults.set(now(), forKey: Self.lastReplaceDateKey)
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

    /// Indexes the snapshot's bookmarked and recent stops, then the cached ones.
    nonisolated private static func fill(
        _ index: any StopEntityIndexing,
        from snapshot: Snapshot,
        stopCache: StopCacheRepository?,
        batchSize: Int
    ) async throws {
        try await submit(snapshot.bookmarked, priority: 3, to: index)
        try await submit(snapshot.recent, priority: 2, to: index)
        if let stopCache {
            try await indexCachedStops(of: snapshot, from: stopCache, into: index, batchSize: batchSize)
        }
    }

    nonisolated private static func submit(_ entities: [StopEntity], priority: Int, to index: any StopEntityIndexing) async throws {
        guard !entities.isEmpty else { return }
        try Task.checkCancellation()
        try await index.index(entities, priority: priority)
    }

    /// Pages through the region's cached stops, skipping any already indexed at
    /// a higher priority, and checks for cancellation between pages. With
    /// `wanted`, it indexes only those stops.
    nonisolated private static func indexCachedStops(
        of snapshot: Snapshot,
        from stopCache: StopCacheRepository,
        into index: any StopEntityIndexing,
        batchSize: Int,
        only wanted: Set<StopID>? = nil
    ) async throws {
        let indexedIDs = Set((snapshot.bookmarked + snapshot.recent).map(\.stopID))
        var cursor: StopID?
        repeat {
            try Task.checkCancellation()
            let page = stopCache.stops(regionId: snapshot.regionID, after: cursor, limit: batchSize)
            let entities = page.stops
                .filter { !indexedIDs.contains($0.id) && (wanted?.contains($0.id) ?? true) }
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

    /// Reads the request before hopping, since a `Notification` isn't `Sendable`.
    /// One it can't read is ignored rather than taken as `.all`, which clears
    /// the index.
    @objc private nonisolated func reindexRequested(_ notification: Notification) {
        guard let scope = StopReindexRequest.scope(from: notification.userInfo) else {
            Logger.warn("Ignoring a Spotlight re-index request with no stops or scope in it.")
            return
        }
        Task { @MainActor [weak self] in
            self?.reindex(scope)
        }
    }
}

extension Notification.Name {
    /// Posted by `StopReindexRequest.post(_:)`. `StopSpotlightIndexer` answers it.
    nonisolated static let stopReindexRequested = Notification.Name("OBA.StopReindexRequested")
}

/// Hands Spotlight's re-index requests from `StopEntityQuery`, which can't reach
/// the app, to `StopSpotlightIndexer`, as `OpenStopRequest` hands Open Stop to
/// `Application`.
///
/// Unlike `OpenStopRequest`'s observer, which `Application.init` adds, this one
/// exists only once `Application.startStopSpotlightIndexing()` creates the
/// indexer in `application(_:didFinishLaunching:)`. A request that arrives
/// earlier in the launch is dropped; that launch indexes every stop anyway.
nonisolated enum StopReindexRequest {
    enum Scope: Equatable, Sendable {
        case all
        case stops([StopEntity.ID])
    }

    private static let allUserInfoKey = "all"
    private static let identifiersUserInfoKey = "identifiers"

    static func post(_ scope: Scope) {
        NotificationCenter.default.post(name: .stopReindexRequested, object: nil, userInfo: userInfo(for: scope))
    }

    /// Spells out `.all`, so a request without a scope can't read as one.
    static func userInfo(for scope: Scope) -> [AnyHashable: Any] {
        switch scope {
        case .all: [allUserInfoKey: true]
        case .stops(let identifiers): [identifiersUserInfoKey: identifiers]
        }
    }

    /// `nil` for a request that names neither.
    static func scope(from userInfo: [AnyHashable: Any]?) -> Scope? {
        if let identifiers = userInfo?[identifiersUserInfoKey] as? [StopEntity.ID] {
            return .stops(identifiers)
        }
        if userInfo?[allUserInfoKey] as? Bool == true {
            return .all
        }
        return nil
    }
}
