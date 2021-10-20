//
//  BookmarkGroupViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 10/6/21.
//

import Foundation
import OBAKitCore

enum BookmarkViewModel: Identifiable, Equatable {
    case stop(StopBookmarkViewModel)
    case trip(TripBookmarkViewModel)

    init(_ bookmark: Bookmark, isLoading: Bool) {
        if bookmark.isTripBookmark {
            let tripBookmark = TripBookmarkViewModel.fromBookmark(bookmark: bookmark, isLoading: isLoading)
            self = .trip(tripBookmark)
        } else {
            let stopBookmark = StopBookmarkViewModel(id: bookmark.id.uuidString, name: bookmark.name, stopID: bookmark.stopID, primaryRouteType: .unknown, isFavorite: bookmark.isFavorite)
            self = .stop(stopBookmark)
        }
    }

    var id: String {
        switch self {
        case .stop(let model): return model.id
        case .trip(let model): return model.id
        }
    }

    var name: String {
        switch self {
        case .stop(let model): return model.name
        case .trip(let model): return model.name
        }
    }

//    var sortOrder: Int {
//        switch self {
//        case .stop(let model): return model.sortOrder
//        case .trip(let model): return model.sortOrder
//        }
//    }
}

struct BookmarkGroupViewModel: Identifiable, Equatable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let bookmarks: [BookmarkViewModel]
}


#if DEBUG
extension BookmarkGroupViewModel {
    static func preview(name: String, sortOrder: Int, bookmarks: [BookmarkViewModel]) -> Self {
        return self.init(id: UUID(), name: name, sortOrder: sortOrder, bookmarks: bookmarks)
    }

    static var previewGroup: [Self] {
        return [
            .preview(name: "To school", sortOrder: 0, bookmarks: [
                .stop(.soundTransitUDistrict),
                .trip(.soundTransit550NoTrips),
                .trip(.metroTransitBLineDepartingLate)]),
            .preview(name: "Bookmarks", sortOrder: 1, bookmarks: [
                .stop(.ferrySeattle),
                .trip(.linkArrivingNowOnTime)
            ])
        ]
    }
}
#endif

