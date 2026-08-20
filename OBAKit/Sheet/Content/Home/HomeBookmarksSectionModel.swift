//
//  HomeBookmarksSectionModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The home sheet's bookmarks preview: the first few bookmarks by the user's
/// own ordering, with live arrivals for those few only.
///
/// Reuses `BookmarkDataLoader` — the same loader the Bookmarks tab uses — but
/// scoped to the displayed bookmarks and with auto-refresh off, so this screen
/// costs at most `limit` requests per activation and installs no polling timer.
///
/// Subclasses `NSObject` to adopt `BookmarkDataDelegate`.
@MainActor
final class HomeBookmarksSectionModel: NSObject, ObservableObject, BookmarkDataDelegate {

    @Published private(set) var rows: [BookmarkRowViewModel] = []

    /// The bookmarks a fetch is scoped to. Read by the loader's provider.
    private(set) var selection: [Bookmark] = []

    private let application: Application
    private let limit: Int

    /// The loader driving this section's arrivals.
    ///
    /// Deliberately `internal`, not `private`: nothing in the app reaches it, and
    /// it exists so `HomeSectionModelTests` can drive a real batch to completion
    /// and assert what this model does with the outcome — in particular the
    /// failed-batch retry path below, which can't be observed from the outside
    /// otherwise. `@testable import` reaches it; the framework's public surface
    /// doesn't grow for a test.
    private(set) var loader: BookmarkDataLoader!

    private var lastFetchDate: Date?
    private var lastFetchedRegionID: Int?

    init(application: Application, limit: Int = HomeSheetSection.itemLimit) {
        self.application = application
        self.limit = limit
        super.init()

        // The provider reads `selection` at fetch time rather than capturing a
        // snapshot, so `refreshSelection()` before a load is enough to rescope
        // the next batch.
        self.loader = BookmarkDataLoader(
            application: application,
            delegate: self,
            bookmarkProvider: { [weak self] in self?.selection ?? [] },
            autoRefreshes: false
        )

        refreshSelection()

        // `.bookmarksDidChange` may be posted off the main actor, so hop rather
        // than assume isolation. This mirrors the pattern in `MapStopsObserver`.
        //
        // Scoped to this application's own store rather than `object: nil`:
        // `UserDefaultsStore` is the only poster and always posts `object: self`,
        // so narrowing costs nothing in the app and keeps a concurrently-running
        // test suite's store from driving this model.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksDidChange),
            name: .bookmarksDidChange,
            object: application.userDataStore
        )
    }

    isolated deinit {
        loader?.cancelUpdates()
    }

    /// Re-reads which bookmarks belong on screen and rebuilds the rows.
    ///
    /// Every pinned bookmark is shown, then unpinned ones fill up to `limit`.
    /// `limit` is therefore a *floor* on the section's size, not a cap: pinning
    /// is the user saying "always keep this one here", so a pin is never squeezed
    /// out by a newer bookmark. With nothing pinned this is just the `limit`
    /// most recent.
    ///
    /// Within each half, most-recently-created first — a bookmark the user just
    /// made should be visible. `sortOrder` can't do that job: `UserDataStore.add`
    /// appends a new bookmark to the end of its group, so ordering by it puts the
    /// newest one *last*, past the cut. It's also renumbered per group, so its
    /// values aren't comparable across groups at all. It still breaks ties,
    /// ascending: bookmarks stored before `dateCreated` existed all decode as
    /// `.distantPast`, and among those the user's own Manage Bookmarks order is
    /// the best signal left.
    func refreshSelection() {
        let all = application.userDataStore
            .findBookmarks(in: application.currentRegion)
            .sorted(by: Self.isOrderedBefore)

        let pinned = all.filter(\.isPinned)
        let unpinned = all.filter { !$0.isPinned }

        selection = pinned + unpinned.prefix(max(0, limit - pinned.count))
        rebuildRows()
    }

    /// Newest first, with the user's manual order breaking same-date ties.
    /// `static` so the ordering can be asserted directly in tests.
    static func isOrderedBefore(_ lhs: Bookmark, _ rhs: Bookmark) -> Bool {
        if lhs.dateCreated != rhs.dateCreated {
            return lhs.dateCreated > rhs.dateCreated
        }
        return lhs.sortOrder < rhs.sortOrder
    }

    // MARK: - Bookmarks

    /// `.bookmarksDidChange` may be posted off the main actor, so hop rather
    /// than assume isolation. Selector-based observation is auto-removed on
    /// dealloc, so no token/deinit needed.
    ///
    /// Goes straight to `loadIfNeeded()`, which re-reads the selection itself.
    /// Calling `refreshSelection()` first would update `selection` *before*
    /// `loadIfNeeded()` snapshots it, so the newly bookmarked stop would never
    /// register as a selection change and its arrivals would never be fetched.
    @objc
    private nonisolated func bookmarksDidChange() {
        Task { @MainActor [weak self] in
            self?.loadIfNeeded()
        }
    }

    /// Fetches arrivals for the current selection, but only when something has
    /// actually changed: the data is stale, the region moved, or the displayed
    /// bookmarks differ. Returns whether a fetch was started.
    ///
    /// The sheet system tears sheet content down and rebuilds it without the
    /// user navigating anywhere, so activation can fire repeatedly per visit —
    /// this gate is what keeps that from becoming repeated network traffic.
    @discardableResult
    func loadIfNeeded(now: Date = Date(), staleAfter: TimeInterval = 30) -> Bool {
        let previousIDs = selection.map(\.id)
        refreshSelection()

        let regionID = application.currentRegion?.regionIdentifier
        let selectionChanged = previousIDs != selection.map(\.id)
        let regionChanged = regionID != lastFetchedRegionID
        let isStale = lastFetchDate.map { now.timeIntervalSince($0) > staleAfter } ?? true

        guard selectionChanged || regionChanged || isStale else { return false }

        lastFetchDate = now
        lastFetchedRegionID = regionID
        loader.loadData()
        return true
    }

    /// Flips `bookmark`'s pinned state.
    ///
    /// No local refresh: the store posts `.bookmarksDidChange`, which this model
    /// already observes, so the reorder arrives through the same path as any
    /// other bookmark edit rather than a second one that could drift from it.
    func togglePin(_ bookmark: Bookmark) {
        application.userDataStore.setPinned(!bookmark.isPinned, for: bookmark)
    }

    // MARK: - Row Building

    /// Rebuilds the row snapshots from the loader's current arrival data.
    ///
    /// `highlightedTripIDs` is always empty: the flash-on-change affordance
    /// belongs to the polling Bookmarks tab, and nothing polls here.
    ///
    /// Guarded against a no-op write for the same reason
    /// `HomeRecentStopsSectionModel.reload()` is: this runs on every activation
    /// and on every loader update, and `BookmarkRowViewModel` is `Equatable`, so
    /// an unchanged rebuild can be dropped rather than republished.
    private func rebuildRows() {
        let rebuilt = selection.map { bookmark in
            BookmarkRowViewModel(
                bookmark: bookmark,
                arrivalDepartures: arrivalDepartures(for: bookmark),
                highlightedTripIDs: [],
                hasLoadedArrivalData: loader.hasFetchedData(forStopID: bookmark.stopID)
            )
        }
        guard rebuilt != rows else { return }
        rows = rebuilt
    }

    private func arrivalDepartures(for bookmark: Bookmark) -> [ArrivalDeparture] {
        guard let key = TripBookmarkKey(bookmark: bookmark) else { return [] }
        return loader.dataForKey(key)
    }

    // MARK: - BookmarkDataDelegate

    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        rebuildRows()
    }

    /// Clears the staleness stamp when a batch finishes having failed, so the
    /// next activation retries instead of being gated out.
    ///
    /// `loadIfNeeded()` stamps `lastFetchDate` *before* the batch resolves — it
    /// has to, or two activations in the same run loop would both fetch. That
    /// stamp is only meaningful if the batch succeeded: without this, a failed
    /// batch left the rows stuck in their "Loading…" state for the rest of the
    /// staleness window, and this sheet has neither the polling timer nor the
    /// pull-to-refresh that bail the Bookmarks tab out of the same situation.
    ///
    /// `lastFetchedRegionID` is deliberately left alone: `isStale` is enough to
    /// reopen the gate, and clearing the region too would make the next
    /// successful fetch look like a region change to any future caller.
    func dataLoader(_ dataLoader: BookmarkDataLoader, isLoadingChanged isLoading: Bool) {
        guard !isLoading, dataLoader.lastBatchHadError else { return }
        lastFetchDate = nil
    }
}
