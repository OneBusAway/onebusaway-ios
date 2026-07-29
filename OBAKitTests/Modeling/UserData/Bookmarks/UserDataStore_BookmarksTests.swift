//
//  UserDataStoreTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try type_name

@Suite(.serialized)
final class UserDefaultsStore_BookmarksTests: OBATestCase {
    var userDefaultsStore: UserDefaultsStore!
    var stops: [Stop]!

    override init() async throws {
        try await super.init()

        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
        stops = try! Fixtures.loadSomeStops()
    }

    // MARK: - Bookmark Groups

    @Test func `Bookmark groups round tripping`() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)

        #expect(self.userDefaultsStore.bookmarkGroups == [])
        userDefaultsStore.upsert(bookmarkGroup: group)
        #expect(self.userDefaultsStore.bookmarkGroups == [group])
    }

    @Test func `Bookmark groups add duplicate`() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)

        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.upsert(bookmarkGroup: group)
        #expect(self.userDefaultsStore.bookmarkGroups == [group])
    }

    @Test func `Bookmark groups delete`() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.deleteGroup(group)
        #expect(self.userDefaultsStore.bookmarkGroups == [])
    }

    @Test func `Bookmark groups delete by ID`() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.deleteGroup(id: group.id)
        #expect(self.userDefaultsStore.bookmarkGroups == [])
    }

    @Test func `Bookmark groups delete nonexistent`() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 1)
        let group2 = BookmarkGroup(name: "Group!", sortOrder: 2)
        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.deleteGroup(group2)
        #expect(self.userDefaultsStore.bookmarkGroups == [group])
    }

    @Test func `Bookmark groups find by ID`() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 1)
        userDefaultsStore.upsert(bookmarkGroup: group)

        let group2 = BookmarkGroup(name: "Group!", sortOrder: 2)
        userDefaultsStore.upsert(bookmarkGroup: group2)

        let found = userDefaultsStore.findGroup(id: group.id)
        #expect(found == group)
    }

    @Test func `Bookmark groups replacement`() {
        // Create and populate
        let keptGroup = BookmarkGroup(name: "kept", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: keptGroup)

        let renamedGroup = BookmarkGroup(name: "i will be renamed", sortOrder: 1)
        userDefaultsStore.upsert(bookmarkGroup: renamedGroup)

        let deletedGroup = BookmarkGroup(name: "deleted", sortOrder: 2)
        userDefaultsStore.upsert(bookmarkGroup: deletedGroup)

        let newGroup = BookmarkGroup(name: "i am new", sortOrder: 3)

        // Verify initial state
        #expect(self.userDefaultsStore.bookmarkGroups == [keptGroup, renamedGroup, deletedGroup])

        // Mutate
        renamedGroup.name = "i have been renamed"

        // Replace state
        userDefaultsStore.replaceBookmarkGroups(with: [keptGroup, renamedGroup, newGroup])

        // Verify new state
        #expect(self.userDefaultsStore.bookmarkGroups == [keptGroup, renamedGroup, newGroup])
        #expect(self.userDefaultsStore.findGroup(id: renamedGroup.id)!.name == "i have been renamed")
        #expect(self.userDefaultsStore.findGroup(id: deletedGroup.id) == nil)
    }

    // MARK: - Bookmarks

    @Test func `Bookmarks retrieval not in group`() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)

        let stop = stops[0]

        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark, to: group, index: .max)

        let bookmark2 = Bookmark(name: "My Bookmark 2", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark2)

        #expect(self.userDefaultsStore.bookmarksInGroup(nil) == [bookmark2])
    }

    @Test func `Bookmarks retrieval in group`() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)

        let stop = stops[0]

        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark, to: group)

        let bookmark2 = Bookmark(name: "My Bookmark 2", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark2)

        #expect(self.userDefaultsStore.bookmarksInGroup(group) == [bookmark])
    }

    @Test func `Bookmarks property round tripping`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        #expect(self.userDefaultsStore.bookmarks == [bookmark])
    }

    @Test func `Bookmark find by ID`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        #expect(self.userDefaultsStore.findBookmark(id: bookmark.id) == bookmark)
    }

    @Test func `Bookmark find by stop ID`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        #expect(self.userDefaultsStore.findBookmark(stopID: stop.id) == bookmark)
    }

    @Test func `Bookmark find no match`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        #expect(self.userDefaultsStore.findBookmark(id: UUID()) == nil)
    }

    @Test func `Bookmark add to group group unregistered`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        let group = BookmarkGroup(name: "My Group", sortOrder: 0)
        userDefaultsStore.add(bookmark, to: group)

        #expect(self.userDefaultsStore.bookmarkGroups == [group])
        #expect(self.userDefaultsStore.bookmarks == [bookmark])
        #expect(self.userDefaultsStore.bookmarksInGroup(group) == [bookmark])
    }

    @Test func `Bookmark change group`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)

        let group = BookmarkGroup(name: "My Group", sortOrder: 0)
        userDefaultsStore.add(bookmark, to: group)

        let group2 = BookmarkGroup(name: "New Group", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group2)

        userDefaultsStore.add(bookmark, to: group2)

        #expect(self.userDefaultsStore.bookmarkGroups == [group, group2])
        #expect(self.userDefaultsStore.bookmarks.first!.id == bookmark.id)
        #expect(self.userDefaultsStore.bookmarksInGroup(group) == [])
        #expect(self.userDefaultsStore.bookmarksInGroup(group2).first!.id == bookmark.id)
    }

    @Test func `Bookmark remove from group`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)

        let group = BookmarkGroup(name: "My Group", sortOrder: 0)
        userDefaultsStore.add(bookmark, to: group)

        userDefaultsStore.add(bookmark, to: nil)

        #expect(self.userDefaultsStore.bookmarkGroups == [group])
        #expect(self.userDefaultsStore.bookmarks.first!.id == bookmark.id)
        #expect(self.userDefaultsStore.bookmarksInGroup(group) == [])
    }

    @Test func `Bookmark add to group group registered`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        let group = BookmarkGroup(name: "My Group", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.add(bookmark, to: group)

        #expect(self.userDefaultsStore.bookmarkGroups == [group])
        #expect(self.userDefaultsStore.bookmarks == [bookmark])
        #expect(self.userDefaultsStore.bookmarksInGroup(group) == [bookmark])
    }

    @Test func `Bookmark add duplicate`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)

        userDefaultsStore.add(bookmark)
        userDefaultsStore.add(bookmark)

        #expect(self.userDefaultsStore.bookmarks == [bookmark])
    }

    @Test func `Bookmark delete`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)

        userDefaultsStore.add(bookmark)
        userDefaultsStore.delete(bookmark: bookmark)

        #expect(self.userDefaultsStore.bookmarks == [])
    }

    @Test func `Bookmark delete nonexistent`() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        let bookmark2 = Bookmark(name: "My Bookmark 2", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)

        userDefaultsStore.add(bookmark)
        userDefaultsStore.delete(bookmark: bookmark2)

        #expect(self.userDefaultsStore.bookmarks == [bookmark])
    }

    @Test func `Bookmark add existing record`() {
        let stop = stops[0]

        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        bookmark.name = "Changed Name"
        userDefaultsStore.add(bookmark)

        #expect(self.userDefaultsStore.bookmarks.count == 1)
        #expect(self.userDefaultsStore.bookmarks.first!.name == "Changed Name")
    }

    // MARK: - Bookmark Sort Order

    @Test func `Bookmark sort order no group`() {
        let stop = stops[0]

        var bookmark0 = Bookmark(name: "Bookmark 0", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark0)

        bookmark0 = userDefaultsStore.findBookmark(id: bookmark0.id)!
        #expect(bookmark0.sortOrder == 0)

        var bookmark1 = Bookmark(name: "Bookmark 1", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark1)

        bookmark1 = userDefaultsStore.findBookmark(id: bookmark1.id)!
        #expect(bookmark1.sortOrder == 1)

        var newBookmark1 = Bookmark(name: "New Bookmark 1", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(newBookmark1, to: nil, index: 1)

        newBookmark1 = userDefaultsStore.findBookmark(id: newBookmark1.id)!
        #expect(newBookmark1.sortOrder == 1)

        bookmark1 = userDefaultsStore.findBookmark(id: bookmark1.id)!
        #expect(bookmark1.sortOrder == 2)

        let ids = userDefaultsStore.bookmarks.map {$0.id}
        #expect(ids == [bookmark0.id, newBookmark1.id, bookmark1.id])

        userDefaultsStore.delete(bookmark: bookmark0)

        newBookmark1 = userDefaultsStore.findBookmark(id: newBookmark1.id)!
        #expect(newBookmark1.sortOrder == 0)

        bookmark1 = userDefaultsStore.findBookmark(id: bookmark1.id)!
        #expect(bookmark1.sortOrder == 1)
    }

    @Test func `Bookmark sort order in group`() {
        let stop = stops[0]
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)

        var bookmark0 = Bookmark(name: "Bookmark 0", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark0, to: group)

        bookmark0 = userDefaultsStore.findBookmark(id: bookmark0.id)!
        #expect(bookmark0.sortOrder == 0)

        var bookmark1 = Bookmark(name: "Bookmark 1", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark1, to: group)

        bookmark1 = userDefaultsStore.findBookmark(id: bookmark1.id)!
        #expect(bookmark1.sortOrder == 1)

        var newBookmark1 = Bookmark(name: "New Bookmark 1", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(newBookmark1, to: group, index: 1)

        newBookmark1 = userDefaultsStore.findBookmark(id: newBookmark1.id)!
        #expect(newBookmark1.sortOrder == 1)

        bookmark1 = userDefaultsStore.findBookmark(id: bookmark1.id)!
        #expect(bookmark1.sortOrder == 2)

        let ids = userDefaultsStore.bookmarksInGroup(group).map {$0.id}
        #expect(ids == [bookmark0.id, newBookmark1.id, bookmark1.id])

        userDefaultsStore.delete(bookmark: bookmark0)

        newBookmark1 = userDefaultsStore.findBookmark(id: newBookmark1.id)!
        #expect(newBookmark1.sortOrder == 0)

        bookmark1 = userDefaultsStore.findBookmark(id: bookmark1.id)!
        #expect(bookmark1.sortOrder == 1)
    }

    @Test func `Bookmark sort order across groups`() {
        let stop = stops[0]
        let group1 = BookmarkGroup(name: "Group 1", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group1)

        let group2 = BookmarkGroup(name: "Group 2", sortOrder: 1)
        userDefaultsStore.upsert(bookmarkGroup: group2)

        let g1b1 = Bookmark(name: "Group 1/Bookmark 1", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(g1b1, to: group1)

        let g1b2 = Bookmark(name: "Group 1/Bookmark 2", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(g1b2, to: group1)
        #expect(g1b2.groupID != nil)
        #expect(g1b2.groupID == group1.id)

        let g1b3 = Bookmark(name: "Group 1/Bookmark 3", regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(g1b3, to: group1)

        #expect(g1b1.sortOrder == 0)
        #expect(g1b2.sortOrder == 1)
        #expect(g1b3.sortOrder == 2)

        userDefaultsStore.add(g1b2, to: group2)

        #expect(self.userDefaultsStore.findBookmark(id: g1b1.id)!.sortOrder == 0)
        #expect(self.userDefaultsStore.findBookmark(id: g1b2.id)!.sortOrder == 0)
        #expect(self.userDefaultsStore.findBookmark(id: g1b3.id)!.sortOrder == 1)
    }
}
