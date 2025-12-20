//
//  BookmarksViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 11/25/20.
//

import Foundation
import OBAKitCore

struct BookmarkArrivalContentConfiguration: OBAContentConfiguration {
    var viewModel: BookmarkArrivalViewModel
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return TripBookmarkTableCell.self
    }
}

/// Used by `OBAListView` to display bookmark data in `BookmarksViewController`.
struct BookmarkArrivalViewModel: OBAListViewItem {
    /// Whether to highlight the time (to indicate a data update) when this item is displayed on the list.
    typealias ArrivalDepartureShouldHighlightPair = (arrDep: ArrivalDeparture, shouldHighlightOnDisplay: Bool)
    let bookmark: Bookmark

    // MARK: - View model properties
    let bookmarkID: UUID
    let name: String
    let regionIdentifier: Int
    let stopID: StopID

    var id: String {
        return "bookmark=\(bookmarkID),region=\(regionIdentifier),stopID=\(stopID)"
    }

    let isFavorite: Bool
    let sortOrder: Int

    let routeShortName: String?
    let tripHeadsign: String?
    let routeID: RouteID?

    // TODO: Same as mentioned above, make arrival departures a struct.
    let arrivalDepartures: [ArrivalDeparture]?
    let arrivalDeparturesPair: [ArrivalDepartureShouldHighlightPair]

    static var customCellType: OBAListViewCell.Type? {
        return TripBookmarkTableCell.self
    }

    var configuration: OBAListViewItemConfiguration {
        return .custom(BookmarkArrivalContentConfiguration(viewModel: self))
    }

    var onSelectAction: OBAListViewAction<BookmarkArrivalViewModel>?
    var onDeleteAction: OBAListViewAction<BookmarkArrivalViewModel>?

    init(bookmark: Bookmark,
         arrivalDepartures: [ArrivalDepartureShouldHighlightPair],
         onSelect: OBAListViewAction<BookmarkArrivalViewModel>?) {
        self.bookmark = bookmark
        self.bookmarkID = bookmark.id
        self.name = bookmark.name
        self.regionIdentifier = bookmark.regionIdentifier
        self.stopID = bookmark.stopID

        self.isFavorite = bookmark.isFavorite
        self.sortOrder = bookmark.sortOrder
        self.routeShortName = bookmark.routeShortName
        self.tripHeadsign = bookmark.tripHeadsign
        self.routeID = bookmark.routeID

        self.arrivalDeparturesPair = arrivalDepartures

        if arrivalDeparturesPair.isEmpty {
            self.arrivalDepartures = nil
        } else {
            self.arrivalDepartures = arrivalDeparturesPair.map { $0.arrDep }
        }

        self.onSelectAction = onSelect
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(isFavorite)
        hasher.combine(sortOrder)
        hasher.combine(routeShortName)
        hasher.combine(tripHeadsign)
        hasher.combine(routeID)
        hasher.combine(arrivalDepartures)
    }

    static func == (lhs: BookmarkArrivalViewModel, rhs: BookmarkArrivalViewModel) -> Bool {
        return
            lhs.bookmarkID == rhs.bookmarkID &&
            lhs.name == rhs.name &&
            lhs.isFavorite == rhs.isFavorite &&
            lhs.sortOrder == rhs.sortOrder &&
            lhs.routeShortName == rhs.routeShortName &&
            lhs.tripHeadsign == rhs.tripHeadsign &&
            lhs.routeID == rhs.routeID &&
            lhs.arrivalDepartures == rhs.arrivalDepartures
    }
}
