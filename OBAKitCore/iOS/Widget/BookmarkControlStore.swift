//
//  BookmarkControlStore.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import Foundation

extension Notification.Name {
    /// Posted by `BookmarkControlOpenRequest.post(_:)`. `Application` opens the stop.
    public static let bookmarkControlOpenRequested = Notification.Name("OBA.BookmarkControlOpenRequested")
}

/// Hands a tapped Bookmark control's stop to `Application`, which
/// `OpenBookmarkControlIntent` can't reach: it runs in the app process, but is
/// compiled into the app target, not OBAKit.
public enum BookmarkControlOpenRequest {
    public static let stopIDUserInfoKey = "stopID"
    public static let regionIDUserInfoKey = "regionID"

    public static func post(_ bookmark: Bookmark, notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .bookmarkControlOpenRequested, object: nil, userInfo: [
            stopIDUserInfoKey: bookmark.stopID,
            regionIDUserInfoKey: bookmark.regionIdentifier
        ])
    }
}

/// Reads bookmarks and the current region from the app-group suite, for the
/// Bookmark control's picker (in the extension) and its tap (in the app).
public enum BookmarkControlStore {
    private static func stored() -> (bookmarks: [Bookmark], regionIdentifier: Int?) {
        guard let suite = Bundle.main.appGroup, let defaults = UserDefaults(suiteName: suite) else {
            return ([], nil)
        }
        let region = ResolvedRegionStore(userDefaults: defaults)
            .region(bundledRegionsFilePath: Bundle.main.path(forResource: "regions", ofType: "json"))
        return (UserDefaultsStore(userDefaults: defaults).bookmarks, region?.regionIdentifier)
    }

    public static func bookmarks() -> [Bookmark] {
        let stored = stored()
        return BookmarkControlCatalog.bookmarks(from: stored.bookmarks, regionIdentifier: stored.regionIdentifier)
    }

    public static func bookmarks(ids: [UUID]) -> [Bookmark] {
        let stored = stored()
        return BookmarkControlCatalog.bookmarks(for: ids, from: stored.bookmarks, regionIdentifier: stored.regionIdentifier)
    }

    public static func bookmarks(matching string: String) -> [Bookmark] {
        let stored = stored()
        return BookmarkControlCatalog.bookmarks(matching: string, from: stored.bookmarks, regionIdentifier: stored.regionIdentifier)
    }
}

#endif // os(iOS)
