//
//  StopAnnotationSync.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The add/remove set `displayUniqueStopAnnotations` should apply. Extracted so
/// a pan that returns the same stop IDs cannot re-add pins (MapKit then
/// recycles views and the icons flash to the default image).
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/563
enum StopAnnotationSync {

    struct BookmarkRef: Equatable {
        var id: UUID
        var stopID: StopID
    }

    struct Changes: Equatable {
        var stopIDsToRemove: Set<StopID>
        var bookmarkIDsToRemove: Set<UUID>
        var stopIDsToAdd: Set<StopID>
        var bookmarkIDsToAdd: Set<UUID>
    }

    static func changes(
        existingStopIDs: Set<StopID>,
        existingBookmarks: [BookmarkRef],
        incomingStopIDs: Set<StopID>,
        bookmarksByStopID: [StopID: UUID],
        selectedStopIDs: Set<StopID>,
        isStopsLayerEnabled: Bool
    ) -> Changes {
        let wantedBookmarkIDs = Set(bookmarksByStopID.values)
        let existingBookmarkIDs = Set(existingBookmarks.map(\.id))
        let selectedBookmarkIDs = Set(
            existingBookmarks
                .filter { selectedStopIDs.contains($0.stopID) }
                .map(\.id)
        )

        var bookmarkIDsToRemove = existingBookmarkIDs.subtracting(wantedBookmarkIDs)
        bookmarkIDsToRemove.subtract(selectedBookmarkIDs)
        let bookmarkIDsToAdd = wantedBookmarkIDs.subtracting(existingBookmarkIDs)

        let bookmarkedStopIDs = Set(bookmarksByStopID.keys)
        var wantedStopIDs: Set<StopID> = []
        if isStopsLayerEnabled {
            wantedStopIDs = incomingStopIDs.subtracting(bookmarkedStopIDs)
        }
        wantedStopIDs.formUnion(selectedStopIDs.subtracting(bookmarkedStopIDs))

        return Changes(
            stopIDsToRemove: existingStopIDs.subtracting(wantedStopIDs),
            bookmarkIDsToRemove: bookmarkIDsToRemove,
            stopIDsToAdd: wantedStopIDs.subtracting(existingStopIDs),
            bookmarkIDsToAdd: bookmarkIDsToAdd
        )
    }
}
