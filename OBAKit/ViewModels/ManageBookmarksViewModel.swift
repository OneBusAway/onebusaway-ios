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
/// Owns: bookmark reordering, deletion (with the `removeBookmark` analytics event),
/// name persistence, and resetting a bookmark's name back to its transit-derived
/// default when the user clears the field.
@MainActor
final class ManageBookmarksViewModel {

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
        if let routeID = bookmark.routeID {
            application.analytics?.reportEvent(
                pageURL: "app://localhost/bookmarks",
                label: AnalyticsLabels.removeBookmark,
                value: AnalyticsLabels.addRemoveBookmarkValue(routeID: routeID, headsign: bookmark.tripHeadsign, stopID: bookmark.stopID)
            )
        }
        application.userDataStore.delete(bookmark: bookmark)
    }

    /// Saves a non-empty, non-whitespace-only name change for the given bookmark.
    /// Empty or whitespace-only names are ignored here; they are restored via
    /// `restoreTransitName(for:)` when the screen closes.
    func saveNameChange(bookmarkID: UUID, newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let bookmark = application.userDataStore.findBookmark(id: bookmarkID) else {
            Logger.warn("saveNameChange: bookmark \(bookmarkID) not found in data store; dropping name edit")
            return
        }

        bookmark.name = newName
        resaveInPlace(bookmark)
    }

    // MARK: - Transit Name Restore

    /// Returns the transit-derived name for `bookmark`:
    /// `"<routeShortName> - <tripHeadsign>"` for trip bookmarks,
    /// or the formatted stop title for stop bookmarks.
    private func originalTransitName(for bookmark: Bookmark) -> String {
        // `isTripBookmark` is defined as all three of `routeShortName`, `routeID`,
        // and `tripHeadsign` being non-nil, so the unwraps here are sound.
        guard bookmark.isTripBookmark else {
            return Formatters.formattedTitle(stop: bookmark.stop)
        }
        return "\(bookmark.routeShortName!) - \(bookmark.tripHeadsign!)"
    }

    /// Resets `bookmark.name` to its transit-derived name and re-saves it to the store.
    func restoreTransitName(for bookmark: Bookmark) {
        bookmark.name = originalTransitName(for: bookmark)
        resaveInPlace(bookmark)
    }

    private func resaveInPlace(_ bookmark: Bookmark) {
        let currentGroup = bookmark.groupID.flatMap { application.userDataStore.findGroup(id: $0) }
        application.userDataStore.add(bookmark, to: currentGroup)
    }
}
