//
//  UserDataStoreBookmarksExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Extended tests for `UserDefaultsStore` bookmark group ordering,
/// orphan bookmark handling, and group replacement edge cases.
@Suite(.serialized)
final class UserDataStoreBookmarksExtendedTests: OBATestCase {

    private var store: UserDefaultsStore!

    override init() async throws {
        try await super.init()
        store = UserDefaultsStore(userDefaults: userDefaults)
    }

    @Test func `Bookmark groups sorted by sortOrder property`() {
        let g3 = BookmarkGroup(name: "Third", sortOrder: 30)
        let g1 = BookmarkGroup(name: "First", sortOrder: 10)
        let g2 = BookmarkGroup(name: "Second", sortOrder: 20)

        store.upsert(bookmarkGroup: g3)
        store.upsert(bookmarkGroup: g1)
        store.upsert(bookmarkGroup: g2)

        let groups = store.bookmarkGroups
        #expect(groups.count == 3)
        #expect(groups[0].name == "First")
        #expect(groups[1].name == "Second")
        #expect(groups[2].name == "Third")
    }

    @Test func `Upserting existing group updates name and sortOrder in place`() {
        let fixedID = UUID()
        let group = BookmarkGroup(name: "Original Name", id: fixedID, sortOrder: 5)
        store.upsert(bookmarkGroup: group)

        #expect(store.bookmarkGroups.count == 1)
        #expect(store.bookmarkGroups.first?.name == "Original Name")

        let updated = BookmarkGroup(name: "Updated Name", id: fixedID, sortOrder: 12)
        store.upsert(bookmarkGroup: updated)

        #expect(store.bookmarkGroups.count == 1)
        #expect(store.bookmarkGroups.first?.name == "Updated Name")
        #expect(store.bookmarkGroups.first?.sortOrder == 12)
    }

    @Test func `Finding nonexistent group by ID returns nil`() {
        let randomID = UUID()
        #expect(store.findGroup(id: randomID) == nil)
    }

    @Test func `Deleting one group leaves other groups intact`() {
        let g1 = BookmarkGroup(name: "Morning", sortOrder: 1)
        let g2 = BookmarkGroup(name: "Evening", sortOrder: 2)

        store.upsert(bookmarkGroup: g1)
        store.upsert(bookmarkGroup: g2)

        store.deleteGroup(g1)

        #expect(store.bookmarkGroups.count == 1)
        #expect(store.bookmarkGroups.first?.id == g2.id)
    }
}
