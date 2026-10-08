//
//  ManageBookmarksViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Observation
import OBAKitCore

/// Shared ViewModel for reordering and deleting bookmarks.
///
/// Owns: the flat list of rows the Bookmarks screen shows, bookmark reordering
/// (within and across groups), deletion (with the `removeBookmark` analytics
/// event), name persistence, and resetting a bookmark's name back to its
/// transit-derived default when the user clears the field.
@MainActor
@Observable
final class ManageBookmarksViewModel {

    /// A bookmark row's editable name. A class so each row observes only its own
    /// name, and so the instance survives `reloadRows()` while its field has focus.
    @MainActor
    @Observable
    final class EditableBookmark: Identifiable {
        let id: UUID
        var name: String

        init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// One row on the Bookmarks screen.
    ///
    /// Groups are header rows in the same list as bookmarks, not `Section`s: SwiftUI
    /// list moves stay within one `ForEach` before iOS 27, and riders drag
    /// bookmarks from one group into another. A bookmark belongs to the nearest
    /// header above it.
    enum Row: Identifiable {
        /// `groupID` is nil for the trailing ungrouped section.
        case header(groupID: UUID?, title: String)
        case bookmark(EditableBookmark)

        var id: String {
            switch self {
            case .header(let groupID, _): "header-\(groupID?.uuidString ?? "ungrouped")"
            case .bookmark(let bookmark): bookmark.id.uuidString
            }
        }
    }

    @ObservationIgnored private let application: Application

    /// The headers' title for bookmarks that aren't in a group.
    @ObservationIgnored private let ungroupedTitle: String

    private(set) var rows: [Row] = []

    init(application: Application, ungroupedTitle: String = BookmarksViewModel.ungroupedSectionTitle) {
        self.application = application
        self.ungroupedTitle = ungroupedTitle
        reloadRows()
    }

    // MARK: - Rows

    /// Rebuilds `rows` from the store: each group's header and bookmarks, then the
    /// ungrouped header and bookmarks. Existing `EditableBookmark`s are reused, so
    /// a field being typed into keeps its identity.
    func reloadRows() {
        var existing = [UUID: EditableBookmark]()
        for case .bookmark(let bookmark) in rows {
            existing[bookmark.id] = bookmark
        }
        // One decode of the store, rather than one per group via `bookmarksInGroup`.
        let bookmarksByGroup = Dictionary(grouping: application.userDataStore.bookmarks, by: \.groupID)
        func bookmarkRows(_ group: BookmarkGroup?) -> [Row] {
            (bookmarksByGroup[group?.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }.map { bookmark in
                let editable = existing[bookmark.id] ?? EditableBookmark(id: bookmark.id, name: bookmark.name)
                return .bookmark(editable)
            }
        }

        var newRows = [Row]()
        for group in bookmarkGroups {
            newRows.append(.header(groupID: group.id, title: group.name))
            newRows.append(contentsOf: bookmarkRows(group))
        }
        newRows.append(.header(groupID: nil, title: ungroupedTitle))
        newRows.append(contentsOf: bookmarkRows(nil))
        rows = newRows
    }

    /// Applies a list move. Headers can't be moved, so `source` is a bookmark; its
    /// destination group is the nearest header above where it lands (the first
    /// group, if it lands above every header).
    func moveRows(from source: IndexSet, to destination: Int) {
        guard
            source.count == 1,
            let sourceIndex = source.first,
            case .bookmark(let moving) = rows[sourceIndex],
            let bookmark = findBookmark(id: moving.id)
        else { return }

        var reordered = rows
        reordered.move(fromOffsets: source, toOffset: destination)
        let landedAt = destination > sourceIndex ? destination - 1 : destination

        // Walk down to where it landed, tracking the current group and the
        // position within it. Rows always open with a header, so a bookmark that
        // lands above every header starts out in the first group.
        guard case .header(var groupID, _) = rows[0] else { return }
        var indexInGroup = 0
        for row in reordered[..<landedAt] {
            switch row {
            case .header(let id, _):
                groupID = id
                indexInGroup = 0
            case .bookmark:
                indexInGroup += 1
            }
        }

        moveBookmark(bookmark, to: findGroup(id: groupID), at: indexInGroup)
        reloadRows()
    }

    /// Deletes the bookmarks at `offsets`; header rows are skipped.
    func deleteRows(at offsets: IndexSet) {
        for index in offsets {
            guard case .bookmark(let row) = rows[index], let bookmark = findBookmark(id: row.id) else { continue }
            deleteBookmark(bookmark)
        }
        reloadRows()
    }

    /// Restores the transit-derived name of every bookmark whose field was left
    /// blank. Call when the rider leaves the screen.
    func restoreEmptyBookmarkNames() {
        for row in rows {
            guard case .bookmark(let editable) = row, editable.name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let bookmark = findBookmark(id: editable.id) else {
                Logger.warn("restoreEmptyBookmarkNames: bookmark \(editable.id) not found in data store; skipping name restore")
                continue
            }
            restoreTransitName(for: bookmark)
            editable.name = bookmark.name
        }
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

        guard bookmark.name != newName else { return }

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
        application.userDataStore.update(bookmark)
    }
}
