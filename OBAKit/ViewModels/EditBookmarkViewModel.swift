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
    case readyToSave(Bookmark, isNewBookmark: Bool)
    case duplicateFound(Bookmark, isNewBookmark: Bool)
}

/// Shared ViewModel for creating and editing a single bookmark.
///
/// Consumed by `EditBookmarkViewController` (UIKit, via direct property reads).
/// Owns: initial form field values, bookmark groups list, duplicate detection,
/// and bookmark persistence. The Eureka form itself stays in the VC.
/// Contains no UIKit or SwiftUI imports.
@MainActor
final class EditBookmarkViewModel {

    // MARK: - Static Context

    /// `true` when creating a new bookmark; `false` when editing an existing one.
    let isAddMode: Bool

    /// Transit-derived name (stop title or route + headsign).
    /// Used as the fallback when the user leaves the name field empty.
    private let dataObjectName: String

    /// Pre-filled initial value for the bookmark name field.
    let initialName: String

    /// UUID string of the initially selected group, or `""` for (No Group).
    let initialGroupID: String

    /// Initial value for the "Show in Today View" toggle.
    let initialIsFavorite: Bool

    // MARK: - Live Data Access

    /// The current list of bookmark groups from the data store. Re-read on every call.
    var bookmarkGroups: [BookmarkGroup] {
        application.userDataStore.bookmarkGroups
    }

    // MARK: - Private

    private let application: Application
    private let source: BookmarkSource
    private let existingBookmark: Bookmark?

    // MARK: - Init

    init(application: Application, source: BookmarkSource, bookmark: Bookmark?) {
        self.application = application
        self.source = source
        self.existingBookmark = bookmark
        self.isAddMode = bookmark == nil
        self.dataObjectName = source.dataObjectName
        self.initialName = bookmark?.name ?? source.dataObjectName
        self.initialIsFavorite = bookmark?.isFavorite ?? true
        self.initialGroupID = bookmark?.groupID?.uuidString ?? ""
    }

    // MARK: - Group Selection

    /// Returns the UUID string of the group currently containing `existingBookmark`
    /// per the data store, or `""` if ungrouped or in add mode.
    /// Call this in `viewWillAppear` to refresh the selection state.
    func currentGroupID() -> String {
        guard let existingBookmark else { return "" }
        return application.userDataStore.bookmarkGroups
            .first { group in
                application.userDataStore.bookmarksInGroup(group).contains { $0.id == existingBookmark.id }
            }?
            .id.uuidString ?? ""
    }

    // MARK: - Save

    /// Builds the `Bookmark` from form values and checks for duplicates.
    /// Returns `nil` if `application.currentRegion` is not available.
    ///
    /// In edit mode this mutates `existingBookmark`'s `name`/`isFavorite` in memory so the
    /// returned bookmark reflects the form values; it does NOT write to the data store.
    /// Call `persist(_:to:isNewBookmark:)` to save, after any duplicate confirmation.
    func prepareToSave(name: String, isFavorite: Bool, selectedGroupID: String) -> SaveOutcome? {
        guard let region = application.currentRegion else { return nil }

        let resolvedName = name.trimmingCharacters(in: .whitespaces).isEmpty ? dataObjectName : name

        if isAddMode {
            let bookmark: Bookmark
            switch source {
            case .stop(let stop):
                bookmark = Bookmark(name: resolvedName, regionIdentifier: region.regionIdentifier, stop: stop)
            case .arrivalDeparture(let ad):
                bookmark = Bookmark(name: resolvedName, regionIdentifier: region.regionIdentifier, arrivalDeparture: ad, stop: ad.stop)
            }
            bookmark.isFavorite = isFavorite
            if application.userDataStore.checkForDuplicates(bookmark: bookmark) {
                return .duplicateFound(bookmark, isNewBookmark: true)
            }
            return .readyToSave(bookmark, isNewBookmark: true)
        } else {
            guard let bookmark = existingBookmark else { return nil }
            bookmark.name = resolvedName
            bookmark.isFavorite = isFavorite
            return .readyToSave(bookmark, isNewBookmark: false)
        }
    }

    /// Saves `bookmark` to the data store and reports analytics for new trip bookmarks.
    func persist(_ bookmark: Bookmark, to groupID: String, isNewBookmark: Bool) {
        let group = UUID(optionalUUIDString: groupID).flatMap { application.userDataStore.findGroup(id: $0) }
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
}
