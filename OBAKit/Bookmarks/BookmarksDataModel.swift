//
//  BookmarksDataModel.swift
//  OBAKit
//
//  Created by Alan Chu on 10/6/21.
//

import Combine
import SwiftUI
import OBAKitCore

class BookmarksDataModel: ObservableObject, BookmarkDataDelegate {
    @Environment(\.coreApplication) var application
    private lazy var dataLoader = BookmarkDataLoader(application: application, delegate: self)

    @Published var groups: [BookmarkGroupViewModel] = []
    private var ungroupedUUID = UUID()

    init() {
        self.groups = []
        updateGroups(isLoading: true)
    }

    func reloadData() {
        updateGroups(isLoading: true)
        dataLoader.loadData()
    }

    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        updateGroups(isLoading: false)
    }

    func updateGroups(isLoading: Bool) {
        let bookmarkGroups = application.userDataStore.bookmarkGroups
        self.groups = bookmarkGroups.map { group in
            let bookmarks = application.userDataStore.bookmarksInGroup(group).map { bookmarkViewModel(bookmark: $0, tripBookmarksIsLoading: isLoading) }
            return BookmarkGroupViewModel(id: group.id, name: group.name, sortOrder: group.sortOrder, bookmarks: bookmarks)
        }

        let ungroupedBookmarks = application.userDataStore.bookmarksInGroup(nil).map { bookmarkViewModel(bookmark: $0, tripBookmarksIsLoading: isLoading) }
        self.groups.append(BookmarkGroupViewModel(id: ungroupedUUID, name: "Ungrouped", sortOrder: self.groups.count, bookmarks: ungroupedBookmarks))
    }

    func bookmarkViewModel(bookmark: Bookmark, tripBookmarksIsLoading: Bool) -> BookmarkViewModel {
        guard bookmark.isTripBookmark else { return BookmarkViewModel(bookmark, isLoading: false) }
        
        var model = TripBookmarkViewModel.fromBookmark(bookmark: bookmark, isLoading: tripBookmarksIsLoading)

        guard let key = TripBookmarkKey(bookmark: bookmark) else { return .trip(model) }

        let arrDeps = dataLoader.dataForKey(key)
        if arrDeps.count >= 1 {
            model.primaryArrivalDeparture = DepartureTimeViewModel(withArrivalDeparture: arrDeps[0])
        }

        if arrDeps.count >= 2 {
            model.secondaryArrivalDeparture = DepartureTimeViewModel(withArrivalDeparture: arrDeps[1])
        }

        if arrDeps.count >= 3 {
            model.tertiaryArrivalDeparture = DepartureTimeViewModel(withArrivalDeparture: arrDeps[2])
        }

        return .trip(model)
    }
}
