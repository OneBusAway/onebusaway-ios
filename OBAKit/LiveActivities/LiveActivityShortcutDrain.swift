//
//  LiveActivityShortcutDrain.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import OBAKitCore
import UIKit

/// Starts a Live Activity queued by the Track Bookmark Shortcut (#1222).
///
/// Runs from `Application` with `topViewController` for alerts — the same
/// shape as `drainPendingUIPresentations`. The Bookmarks tab cannot be the
/// only drain: `rootNavigateTo(.bookmarks)` does not pop a pushed stop page,
/// so that tab's lifecycle callbacks never fire.
enum LiveActivityShortcutDrain {

    /// Drops a request that cannot start, or fetches arrivals and starts the
    /// activity. Does not switch tabs.
    @MainActor
    static func consume(application: Application, presentingFrom presenter: UIViewController?) {
        guard let id = LiveActivityShortcutRequest.peek(userDefaults: application.userDefaults) else { return }
        guard let bookmark = application.userDataStore.findBookmark(id: id) else {
            LiveActivityShortcutRequest.clear(application.userDefaults)
            return
        }

        let currentRegionID = application.currentRegion?.regionIdentifier
        if bookmark.regionIdentifier != currentRegionID {
            Logger.warn("Track Bookmark Shortcut: bookmark \(id) is region \(String(describing: bookmark.regionIdentifier)); current region is \(String(describing: currentRegionID)). Dropping the queued request.")
            LiveActivityShortcutRequest.clear(application.userDefaults)
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.warn("Track Bookmark Shortcut: Live Activities are disabled. Dropping the queued request \(id). Enable Live Activities for this app in iOS Settings to use Track Bookmark.")
            LiveActivityShortcutRequest.clear(application.userDefaults)
            return
        }

        Task { @MainActor in
            await start(bookmark: bookmark, id: id, application: application, presentingFrom: presenter)
        }
    }

    @MainActor
    private static func start(
        bookmark: Bookmark,
        id: UUID,
        application: Application,
        presentingFrom presenter: UIViewController?
    ) async {
        let loader = BookmarkDataLoader(
            application: application,
            delegate: DrainLoaderDelegate.shared,
            bookmarkProvider: { [bookmark] in [bookmark] },
            autoRefreshes: false
        )
        await loader.loadDataAndWait()

        guard LiveActivityShortcutRequest.peek(userDefaults: application.userDefaults) == id else { return }
        LiveActivityShortcutRequest.clear(application.userDefaults)

        let arrivals: [ArrivalDeparture]
        if let key = TripBookmarkKey(bookmark: bookmark) {
            arrivals = loader.dataForKey(key)
        } else {
            arrivals = []
        }

        let result = BookmarkActions(application: application)
            .startLiveActivity(for: bookmark, arrivalDepartures: arrivals)
        if result == .failed {
            presenter?.showLiveActivityErrorAlert()
        }
    }
}

/// `BookmarkDataLoader` requires a delegate; this drain waits on
/// `loadDataAndWait()` instead of delegate callbacks.
private final class DrainLoaderDelegate: NSObject, BookmarkDataDelegate {
    static let shared = DrainLoaderDelegate()
    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {}
}
