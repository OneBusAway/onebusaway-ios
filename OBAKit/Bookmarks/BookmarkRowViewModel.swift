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

/// What a destination bookmark's card says about arriving at the destination.
enum BookmarkDestinationStatus: Equatable {
    /// The next departure's trip schedule hasn't loaded yet.
    case loading

    /// The next departure reaches the destination at this time.
    case arrives(DestinationArrival)

    /// None of the upcoming departures stop at the destination.
    case notServed
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

    /// Whether the user pinned this bookmark to the top of the home sheet's
    /// bookmarks section. Carried into the row so the cell can show the glyph and
    /// the context menu can offer the right verb.
    let isPinned: Bool

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

    /// The destination stop's name for a bookmark that tracks one; `nil` otherwise.
    let destinationStopName: String?

    /// Arrival at the destination for the first departure in `arrivalDepartures`.
    /// `nil` for bookmarks without a destination, and while there are no departures.
    let destinationStatus: BookmarkDestinationStatus?

    /// - Parameter destinationLookup: For a bookmark with a destination, reports
    ///   whether each departure reaches it. Departures known not to reach it are
    ///   dropped, so the card never offers a bus that won't get the rider home.
    init(
        bookmark: Bookmark,
        arrivalDepartures: [ArrivalDeparture],
        highlightedTripIDs: Set<TripIdentifier>,
        hasLoadedArrivalData: Bool = false,
        destinationLookup: ((ArrivalDeparture) -> DestinationArrivalLookup)? = nil
    ) {
        self.bookmark = bookmark
        self.id = bookmark.id
        self.name = bookmark.name
        self.stopID = bookmark.stopID
        self.isTripBookmark = bookmark.isTripBookmark
        self.isFavorite = bookmark.isFavorite
        self.isPinned = bookmark.isPinned
        self.routeShortName = bookmark.routeShortName
        // Self-enforce "always empty for whole-stop bookmarks" rather than
        // trusting the caller.
        let tripArrivalDepartures = bookmark.isTripBookmark ? arrivalDepartures : []

        if bookmark.hasDestination, let destinationLookup {
            let lookups = tripArrivalDepartures.map { ($0, destinationLookup($0)) }
            let reachable = lookups.filter { $0.1 != .notServed }
            self.arrivalDepartures = reachable.map(\.0)
            self.destinationStopName = bookmark.destinationStopName

            switch reachable.first?.1 {
            case .arrives(let arrival):
                self.destinationStatus = .arrives(arrival)
            case .pending:
                self.destinationStatus = .loading
            case .unavailable:
                // The schedule couldn't be loaded; the departure still stands,
                // so show it without an arrival line rather than a spinner
                // that will never resolve.
                self.destinationStatus = nil
            case .notServed, nil:
                self.destinationStatus = lookups.isEmpty ? nil : .notServed
            }
        } else {
            self.arrivalDepartures = tripArrivalDepartures
            self.destinationStopName = bookmark.hasDestination ? bookmark.destinationStopName : nil
            self.destinationStatus = nil
        }
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
        lhs.isPinned == rhs.isPinned &&
        lhs.routeShortName == rhs.routeShortName &&
        lhs.arrivalDepartures == rhs.arrivalDepartures &&
        lhs.hasLoadedArrivalData == rhs.hasLoadedArrivalData &&
        lhs.highlightedTripIDs == rhs.highlightedTripIDs &&
        lhs.routesSubtitle == rhs.routesSubtitle &&
        lhs.destinationStopName == rhs.destinationStopName &&
        lhs.destinationStatus == rhs.destinationStatus
    }
}
