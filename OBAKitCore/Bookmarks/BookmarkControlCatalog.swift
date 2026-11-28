//
//  BookmarkControlCatalog.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The bookmark lookups behind the widget extension's Bookmark control
/// (Control Center, the Lock Screen and the Action button).
///
/// Pure Foundation logic so `OBAKitTests` (which links `OBAKitCore` rather
/// than `OBAWidget`) can exercise it directly, like `WidgetBookmarkPaginator`.
///
/// Unlike Track Bookmark, any bookmark can back a control, stop or trip:
/// the control only opens the bookmark's stop.
public enum BookmarkControlCatalog {
    /// Most bookmarks the picker's search returns at once.
    public static let searchResultLimit = 20

    /// The bookmarks a control can be set to: those in `regionIdentifier`, in
    /// stored order. None without a region, since the app can only open a stop
    /// in the region it is in.
    public static func bookmarks(from bookmarks: [Bookmark], regionIdentifier: Int?) -> [Bookmark] {
        guard let regionIdentifier else { return [] }
        return bookmarks.filter { $0.regionIdentifier == regionIdentifier }
    }

    /// The bookmark for each of `identifiers` that is still offered, in the
    /// order asked. A deleted bookmark, or one from another region, is left out.
    public static func bookmarks(for identifiers: [UUID], from bookmarks: [Bookmark], regionIdentifier: Int?) -> [Bookmark] {
        let offered = self.bookmarks(from: bookmarks, regionIdentifier: regionIdentifier)
        let byID = Dictionary(offered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { byID[$0] }
    }

    /// Offered bookmarks whose name or stop name contains `query`.
    public static func bookmarks(matching query: String, from bookmarks: [Bookmark], regionIdentifier: Int?) -> [Bookmark] {
        let hits = self.bookmarks(from: bookmarks, regionIdentifier: regionIdentifier).filter {
            $0.name.localizedStandardContains(query) || $0.stop.name.localizedStandardContains(query)
        }
        return Array(hits.prefix(searchResultLimit))
    }
}
