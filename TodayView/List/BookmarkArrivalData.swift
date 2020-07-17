//
//  BookmarkArrivalData.swift
//  TodayView
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import IGListKit
import OBAKitCore

typealias BookmarkListCallback = (Bookmark) -> Void

/// A view model used with `IGListKit` to display `Bookmark` data in the `BookmarksViewController`.
class BookmarkArrivalData: NSObject, ListDiffable {
    public let bookmark: Bookmark
    public let arrivalDepartures: [ArrivalDeparture]?
    let selected: BookmarkListCallback

    public init(bookmark: Bookmark, arrivalDepartures: [ArrivalDeparture]?, selected: @escaping BookmarkListCallback) {
        self.bookmark = bookmark
        self.arrivalDepartures = arrivalDepartures
        self.selected = selected
    }

    public func diffIdentifier() -> NSObjectProtocol {
        bookmark.id as NSObjectProtocol
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? BookmarkArrivalData else {
            return false
        }

        return bookmark == object.bookmark && arrivalDepartures == object.arrivalDepartures
    }

    override var debugDescription: String {
        var descriptionBuilder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
        descriptionBuilder.add(key: "bookmark", value: bookmark)
        descriptionBuilder.add(key: "arrivalDepartures", value: arrivalDepartures)
        return descriptionBuilder.description
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(bookmark)
        hasher.combine(arrivalDepartures)
        return hasher.finalize()
    }
}
