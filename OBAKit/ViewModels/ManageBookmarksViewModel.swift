//
//  ManageBookmarksViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Shared ViewModel for reordering and deleting bookmarks.
///
/// Consumed by `ManageBookmarksViewController` (UIKit, via direct calls).
/// Owns: bookmark reordering, deletion (with analytics), name persistence,
/// and transit-name restore logic. The Eureka form UX stays in the VC.
/// Contains no UIKit or SwiftUI imports.
@MainActor
class ManageBookmarksViewModel {

    private let application: Application

    init(application: Application) {
        self.application = application
    }

    // MARK: - Data Access

    var bookmarkGroups: [BookmarkGroup] {
        application.userDataStore.bookmarkGroups
    }

    func bookmarksInGroup(_ group: BookmarkGroup?) -> [Bookmark] {
        application.userDataStore.bookmarksInGroup(group)
    }

    func findGroup(id: UUID?) -> BookmarkGroup? {
        application.userDataStore.findGroup(id: id)
    }

    func findBookmark(id: UUID) -> Bookmark? {
        application.userDataStore.findBookmark(id: id)
    }

    // MARK: - Mutations

    func moveBookmark(_ bookmark: Bookmark, to group: BookmarkGroup?, at index: Int) {
        application.userDataStore.add(bookmark, to: group, index: index)
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        if let routeID = bookmark.routeID, let headsign = bookmark.tripHeadsign {
            application.analytics?.reportEvent(
                pageURL: "app://localhost/bookmarks",
                label: AnalyticsLabels.removeBookmark,
                value: AnalyticsLabels.addRemoveBookmarkValue(routeID: routeID, headsign: headsign, stopID: bookmark.stopID)
            )
        }
        application.userDataStore.delete(bookmark: bookmark)
    }

    /// Saves a non-empty, non-whitespace-only name change for the given bookmark.
    /// Empty or whitespace-only names are ignored here; they are restored via
    /// `restoreTransitName(for:)` when the screen closes.
    func saveNameChange(bookmarkID: UUID, newName: String) {
        guard
            !newName.trimmingCharacters(in: .whitespaces).isEmpty,
            let bookmark = application.userDataStore.findBookmark(id: bookmarkID)
        else { return }

        bookmark.name = newName
        let currentGroup = bookmark.groupID.flatMap { application.userDataStore.findGroup(id: $0) }
        application.userDataStore.add(bookmark, to: currentGroup)
    }

    // MARK: - Transit Name Restore

    /// Returns the transit-derived name for `bookmark`:
    /// `"<routeShortName> - <tripHeadsign>"` for trip bookmarks,
    /// or the formatted stop title for stop bookmarks.
    private func originalTransitName(for bookmark: Bookmark) -> String {
        if bookmark.isTripBookmark,
           let routeShortName = bookmark.routeShortName,
           let tripHeadsign = bookmark.tripHeadsign {
            return "\(routeShortName) - \(tripHeadsign)"
        }
        return Formatters.formattedTitle(stop: bookmark.stop)
    }

    /// Resets `bookmark.name` to its transit-derived name and re-saves it to the store.
    func restoreTransitName(for bookmark: Bookmark) {
        bookmark.name = originalTransitName(for: bookmark)
        let currentGroup = bookmark.groupID.flatMap { application.userDataStore.findGroup(id: $0) }
        application.userDataStore.add(bookmark, to: currentGroup)
    }
}
