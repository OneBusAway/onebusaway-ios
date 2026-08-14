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
    private var loader: BookmarkDataLoader!

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
    }

    isolated deinit {
        loader?.cancelUpdates()
    }

    /// Re-reads which bookmarks belong on screen and rebuilds the rows.
    ///
    /// `findBookmarks(in:)` returns raw persisted order — only `bookmarksInGroup`
    /// sorts — so the sort here is what makes the four shown match the user's
    /// Manage Bookmarks ordering.
    func refreshSelection() {
        selection = Array(
            application.userDataStore
                .findBookmarks(in: application.currentRegion)
                .sorted { $0.sortOrder < $1.sortOrder }
                .prefix(limit)
        )
        rebuildRows()
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

    // MARK: - Row Building

    /// Rebuilds the row snapshots from the loader's current arrival data.
    ///
    /// `highlightedTripIDs` is always empty: the flash-on-change affordance
    /// belongs to the polling Bookmarks tab, and nothing polls here.
    private func rebuildRows() {
        rows = selection.map { bookmark in
            BookmarkRowViewModel(
                bookmark: bookmark,
                arrivalDepartures: arrivalDepartures(for: bookmark),
                highlightedTripIDs: [],
                hasLoadedArrivalData: loader.hasFetchedData(forStopID: bookmark.stopID)
            )
        }
    }

    private func arrivalDepartures(for bookmark: Bookmark) -> [ArrivalDeparture] {
        guard let key = TripBookmarkKey(bookmark: bookmark) else { return [] }
        return loader.dataForKey(key)
    }

    // MARK: - BookmarkDataDelegate

    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        rebuildRows()
    }
}
