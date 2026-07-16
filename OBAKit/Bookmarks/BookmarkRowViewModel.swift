//
//  BookmarkRowViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// A section of the Bookmarks list: one bookmark group, the ungrouped bucket,
/// or the single distance-sorted bucket. `id` values match the legacy
/// `OBAListViewSection` IDs (group UUID string, `"unknown_group"`,
/// `"distance_sorted_group"`) so collapse state persisted by the old screen
/// carries over unchanged.
struct BookmarkListSection: Identifiable, Equatable {
    let id: String
    let title: String
    let rows: [BookmarkRowViewModel]
}

/// Immutable per-row snapshot for the Bookmarks list, built by
/// `BookmarksViewModel.rebuildSections()` from a `Bookmark` plus the data
/// loader's current arrival/departures. Views receive plain values only.
struct BookmarkRowViewModel: Identifiable, Equatable {
    /// The backing bookmark, kept for the navigation/edit/delete/track
    /// callbacks. Reference type — equality is never defined over this object,
    /// only over all of the copied value fields below.
    let bookmark: Bookmark

    let id: UUID
    let name: String
    let stopID: StopID
    let isTripBookmark: Bool
    let isFavorite: Bool
    let routeShortName: String?

    /// Upcoming arrival/departures for a trip bookmark. Empty until data lands,
    /// and always empty for whole-stop bookmarks.
    let arrivalDepartures: [ArrivalDeparture]

    /// `true` once an arrival fetch for this bookmark's stop has completed, so
    /// the card can distinguish "Loading…" from "loaded, but no upcoming
    /// departures". Always `false` for whole-stop bookmarks (nothing fetches).
    let hasLoadedArrivalData: Bool

    /// Trip IDs whose displayed minutes changed in the latest refresh; the card
    /// flashes those badges when displayed.
    let highlightedTripIDs: Set<TripIdentifier>

    /// Formatted route list ("10, 21, 49") for whole-stop bookmark rows;
    /// `nil` for trip bookmarks.
    let routesSubtitle: String?

    init(bookmark: Bookmark, arrivalDepartures: [ArrivalDeparture], highlightedTripIDs: Set<TripIdentifier>, hasLoadedArrivalData: Bool = false) {
        self.bookmark = bookmark
        self.id = bookmark.id
        self.name = bookmark.name
        self.stopID = bookmark.stopID
        self.isTripBookmark = bookmark.isTripBookmark
        self.isFavorite = bookmark.isFavorite
        self.routeShortName = bookmark.routeShortName
        // Self-enforce "always empty for whole-stop bookmarks" rather than
        // trusting the caller.
        self.arrivalDepartures = bookmark.isTripBookmark ? arrivalDepartures : []
        self.hasLoadedArrivalData = bookmark.isTripBookmark && hasLoadedArrivalData
        self.highlightedTripIDs = highlightedTripIDs
        self.routesSubtitle = bookmark.isTripBookmark ? nil : Formatters.formattedRoutes(bookmark.stop.routes)
    }

    static func == (lhs: BookmarkRowViewModel, rhs: BookmarkRowViewModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.stopID == rhs.stopID &&
        lhs.isTripBookmark == rhs.isTripBookmark &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.routeShortName == rhs.routeShortName &&
        lhs.arrivalDepartures == rhs.arrivalDepartures &&
        lhs.hasLoadedArrivalData == rhs.hasLoadedArrivalData &&
        lhs.highlightedTripIDs == rhs.highlightedTripIDs &&
        lhs.routesSubtitle == rhs.routesSubtitle
    }
}
