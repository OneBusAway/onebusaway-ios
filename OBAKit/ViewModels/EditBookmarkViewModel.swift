//
//  EditBookmarkViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import OBAKitCore

/// Describes what is being bookmarked. Using a tagged enum instead of two optionals
/// makes the dual-nil state unrepresentable at the call site.
enum BookmarkSource {
    case stop(Stop)
    case arrivalDeparture(ArrivalDeparture)

    var dataObjectName: String {
        switch self {
        case .stop(let stop):
            return Formatters.formattedTitle(stop: stop)
        case .arrivalDeparture(let arrival):
            return arrival.routeAndHeadsign
        }
    }
}

enum SaveOutcome {
    case regionUnavailable
    case readyToSave(Bookmark, isNew: Bool)
    case duplicateRequiresConfirmation(Bookmark)
}

/// Shared ViewModel for creating and editing a single bookmark.
///
/// Owns: initial form field values, the live list of bookmark groups, duplicate
/// detection against the data store, and bookmark persistence (including the
/// `addBookmark` analytics event for new trip bookmarks).
@MainActor
final class EditBookmarkViewModel {

    // MARK: - Static Context

    /// `true` when creating a new bookmark; `false` when editing an existing one.
    var isAddMode: Bool {
        if case .add = mode { return true }
        return false
    }

    /// Transit-derived name (stop title or route + headsign).
    /// Used as the fallback when the user leaves the name field empty.
    private let dataObjectName: String

    /// Pre-filled initial value for the bookmark name field.
    let initialName: String

    /// UUID of the initially selected group, or `nil` for (No Group).
    let initialGroupID: UUID?

    /// Initial value for the "Show in Today View" toggle.
    let initialIsFavorite: Bool

    // MARK: - Live Data Access

    /// The current list of bookmark groups from the data store. Re-read on every call.
    var bookmarkGroups: [BookmarkGroup] {
        application.userDataStore.bookmarkGroups
    }

    // MARK: - Private

    private enum Mode {
        case add
        case edit(Bookmark)
    }

    private let application: Application
    private let source: BookmarkSource
    private let mode: Mode

    // MARK: - Init

    init(application: Application, source: BookmarkSource, bookmark: Bookmark?) {
        self.application = application
        self.source = source
        self.mode = bookmark.map(Mode.edit) ?? .add
        self.dataObjectName = source.dataObjectName
        self.initialName = bookmark?.name ?? source.dataObjectName
        self.initialIsFavorite = bookmark?.isFavorite ?? true
        self.initialGroupID = bookmark?.groupID
    }

    // MARK: - Group Selection

    /// Returns the data store's live view of which group currently contains the
    /// bookmark being edited, or `nil` if ungrouped or in add mode. Distinct from
    /// the cached `initialGroupID` captured at init time, which may be stale if
    /// the user moved the bookmark in another screen.
    func currentGroupID() -> UUID? {
        guard case .edit(let bookmark) = mode else { return nil }
        return application.userDataStore.bookmarkGroups
            .first { group in
                application.userDataStore.bookmarksInGroup(group).contains { $0.id == bookmark.id }
            }?
            .id
    }

    // MARK: - Save

    /// Validates that a region is available and, in add mode, builds the `Bookmark`
    /// and checks for duplicates against the data store.
    ///
    /// Does NOT mutate the existing bookmark or write to the data store. The form
    /// values (`name`, `isFavorite`) are applied to the bookmark inside
    /// `persist(_:name:isFavorite:to:isNewBookmark:)`.
    func prepareToSave(name: String, isFavorite: Bool) -> SaveOutcome {
        guard let region = application.currentRegion else { return .regionUnavailable }

        switch mode {
        case .add:
            let resolvedName = resolveName(name)
            let bookmark: Bookmark
            switch source {
            case .stop(let stop):
                bookmark = Bookmark(name: resolvedName, regionIdentifier: region.regionIdentifier, stop: stop)
            case .arrivalDeparture(let ad):
                bookmark = Bookmark(name: resolvedName, regionIdentifier: region.regionIdentifier, arrivalDeparture: ad, stop: ad.stop)
            }
            if application.userDataStore.checkForDuplicates(bookmark: bookmark) {
                return .duplicateRequiresConfirmation(bookmark)
            }
            return .readyToSave(bookmark, isNew: true)
        case .edit(let bookmark):
            return .readyToSave(bookmark, isNew: false)
        }
    }

    /// Applies the form values to `bookmark`, saves it to the data store, and
    /// reports analytics for new trip bookmarks.
    func persist(_ bookmark: Bookmark, name: String, isFavorite: Bool, to groupID: UUID?, isNewBookmark: Bool) {
        bookmark.name = resolveName(name)
        bookmark.isFavorite = isFavorite

        let group = groupID.flatMap { application.userDataStore.findGroup(id: $0) }
        application.userDataStore.add(bookmark, to: group)

        if isNewBookmark, case .arrivalDeparture(let ad) = source {
            let value = AnalyticsLabels.addRemoveBookmarkValue(
                routeID: ad.routeID,
                headsign: ad.tripHeadsign,
                stopID: ad.stopID
            )
            application.analytics?.reportEvent(
                pageURL: "app://localhost/bookmarks",
                label: AnalyticsLabels.addBookmark,
                value: value
            )
        }
    }

    private func resolveName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? dataObjectName : name
    }
}
