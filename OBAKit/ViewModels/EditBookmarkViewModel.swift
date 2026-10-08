//
//  EditBookmarkViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Observation
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

    /// Stop ID the bookmark will (or already does) request arrivals for.
    var stopID: StopID {
        switch self {
        case .stop(let stop):
            return stop.id
        case .arrivalDeparture(let arrival):
            return arrival.stopID
        }
    }
}

/// Outcome of validating a save. New vs existing is a separate case so a
/// `(bookmark, isNew)` pair can never disagree (#1145).
enum SaveOutcome {
    case regionUnavailable
    case readyToSaveNew(Bookmark)
    case readyToSaveExisting(Bookmark)
    case duplicateRequiresConfirmation(Bookmark)
}

/// User response to the duplicate-bookmark alert. Cancel must not persist or
/// fire analytics (#1145 / #1138).
enum DuplicateBookmarkDecision {
    case cancelled
    case createDuplicate(Bookmark)
}

/// Shared ViewModel for creating and editing a single bookmark.
///
/// Owns: the form's state (name, Today View switch, group), the groups offered, duplicate
/// detection against the data store, and bookmark persistence (including the
/// `addBookmark` analytics event for new trip bookmarks).
@MainActor
@Observable
final class EditBookmarkViewModel {

    // MARK: - Form State

    /// The name field's text. Blank saves as the transit-derived name.
    var name: String

    /// The "Show in Today View widget" switch.
    var isFavorite: Bool

    /// The checked group, or `nil` for (No Group).
    var selectedGroupID: UUID?

    /// The groups offered in the picker, in display order. Refreshed when the
    /// rider adds one, since `BookmarkGroup` isn't observable.
    private(set) var groups: [BookmarkGroup]

    // MARK: - Static Context

    /// `true` when creating a new bookmark; `false` when editing an existing one.
    var isAddMode: Bool {
        if case .add = mode { return true }
        return false
    }

    /// Transit-derived name (stop title or route + headsign).
    /// Used as the fallback when the user leaves the name field empty.
    private let dataObjectName: String

    /// Stop ID used for arrivals-and-departures requests. Shown in the editor
    /// so a broken bookmark can be identified without trial-and-error deletes (#1421).
    let stopID: StopID

    // MARK: - Private

    private enum Mode {
        case add
        case edit(Bookmark)
    }

    @ObservationIgnored private let application: Application
    @ObservationIgnored private let source: BookmarkSource
    @ObservationIgnored private let mode: Mode

    // MARK: - Init

    init(application: Application, source: BookmarkSource, bookmark: Bookmark?) {
        self.application = application
        self.source = source
        self.mode = bookmark.map(Mode.edit) ?? .add
        self.dataObjectName = source.dataObjectName
        self.stopID = bookmark?.stopID ?? source.stopID
        self.name = bookmark?.name ?? source.dataObjectName
        self.isFavorite = bookmark?.isFavorite ?? true

        let groups = application.userDataStore.bookmarkGroups
        self.groups = groups
        // The store's view of the bookmark's group, not `bookmark.groupID`: the
        // rider may have moved it on another screen since it was handed to us.
        // A group that no longer exists shows as (No Group).
        let storedGroupID = bookmark.flatMap { application.userDataStore.findBookmark(id: $0.id)?.groupID }
        self.selectedGroupID = groups.contains { $0.id == storedGroupID } ? storedGroupID : nil
    }

    // MARK: - Groups

    /// Creates a group named `name`, appended after the existing ones, and
    /// offers it in the picker. Blank names are ignored.
    func addGroup(named name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        application.userDataStore.upsert(bookmarkGroup: BookmarkGroup(name: name, sortOrder: Int.max))
        groups = application.userDataStore.bookmarkGroups
    }

    // MARK: - Save

    /// Validates that a region is available and, in add mode, builds the `Bookmark`
    /// and checks for duplicates against the data store.
    ///
    /// Does NOT mutate the existing bookmark or write to the data store; `name`
    /// is applied inside `persist`.
    func prepareToSave(name: String) -> SaveOutcome {
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
            return .readyToSaveNew(bookmark)
        case .edit(let bookmark):
            return .readyToSaveExisting(bookmark)
        }
    }

    /// Applies the form values to `bookmark`, saves it, and reports analytics for
    /// new trip bookmarks. Prefer the typed `SaveOutcome` / `DuplicateBookmarkDecision`
    /// helpers so callers can't pass a mismatched new/existing flag.
    func persistNew(_ bookmark: Bookmark, name: String, isFavorite: Bool, to groupID: UUID?) {
        persist(bookmark, name: name, isFavorite: isFavorite, to: groupID, reportAddAnalytics: true)
    }

    func persistExisting(_ bookmark: Bookmark, name: String, isFavorite: Bool, to groupID: UUID?) {
        persist(bookmark, name: name, isFavorite: isFavorite, to: groupID, reportAddAnalytics: false)
    }

    /// Handles the duplicate alert. Cancel is a no-op (no store write, no analytics).
    func resolveDuplicate(
        _ decision: DuplicateBookmarkDecision,
        name: String,
        isFavorite: Bool,
        to groupID: UUID?
    ) {
        switch decision {
        case .cancelled:
            return
        case .createDuplicate(let bookmark):
            persistNew(bookmark, name: name, isFavorite: isFavorite, to: groupID)
        }
    }

    private func persist(
        _ bookmark: Bookmark,
        name: String,
        isFavorite: Bool,
        to groupID: UUID?,
        reportAddAnalytics: Bool
    ) {
        bookmark.name = resolveName(name)
        bookmark.isFavorite = isFavorite

        let store = application.userDataStore
        if let stored = store.findBookmark(id: bookmark.id), stored.groupID == groupID {
            // Same group: save in place. `add(_:to:)` would move it to the
            // bottom of its group.
            stored.name = bookmark.name
            stored.isFavorite = bookmark.isFavorite
            store.update(stored)
        } else {
            store.add(bookmark, to: groupID.flatMap { store.findGroup(id: $0) })
        }

        if reportAddAnalytics, case .arrivalDeparture(let ad) = source {
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
