//
//  UserDataStoreTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 5/20/19.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try type_name

class UserDefaultsStore_BookmarksTests: OBATestCase {

    var userDefaultsStore: UserDefaultsStore!
    var tampaRegion: Region!
    var pugetSoundRegion: Region!
    var stops: [Stop]!

    override func setUp() {
        super.setUp()
        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)

        let regions = try! loadSomeRegions()
        tampaRegion = regions[0]
        pugetSoundRegion = regions[1]

        stops = try! loadSomeStops()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Bookmark Groups

    func test_bookmarkGroups_roundTripping() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)

        expect(self.userDefaultsStore.bookmarkGroups) == []
        userDefaultsStore.upsert(bookmarkGroup: group)
        expect(self.userDefaultsStore.bookmarkGroups) == [group]
    }

    func test_bookmarkGroups_addDuplicate() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)

        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.upsert(bookmarkGroup: group)
        expect(self.userDefaultsStore.bookmarkGroups) == [group]

    }

    func test_bookmarkGroups_delete() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.deleteGroup(group)
        expect(self.userDefaultsStore.bookmarkGroups) == []
    }

    func test_bookmarkGroups_deleteByID() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.deleteGroup(id: group.id)
        expect(self.userDefaultsStore.bookmarkGroups) == []
    }

    func test_bookmarkGroups_deleteNonexistent() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 1)
        let group2 = BookmarkGroup(name: "Group!", sortOrder: 2)
        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.deleteGroup(group2)
        expect(self.userDefaultsStore.bookmarkGroups) == [group]
    }

    func test_bookmarkGroups_findByID() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 1)
        userDefaultsStore.upsert(bookmarkGroup: group)

        let group2 = BookmarkGroup(name: "Group!", sortOrder: 2)
        userDefaultsStore.upsert(bookmarkGroup: group2)

        let found = userDefaultsStore.findGroup(id: group.id)
        expect(found) == group
    }

    func test_bookmarkGroups_replacement() {
        // Create and populate
        let keptGroup = BookmarkGroup(name: "kept", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: keptGroup)

        let renamedGroup = BookmarkGroup(name: "i will be renamed", sortOrder: 1)
        userDefaultsStore.upsert(bookmarkGroup: renamedGroup)

        let deletedGroup = BookmarkGroup(name: "deleted", sortOrder: 2)
        userDefaultsStore.upsert(bookmarkGroup: deletedGroup)

        let newGroup = BookmarkGroup(name: "i am new", sortOrder: 3)

        // Verify initial state
        expect(self.userDefaultsStore.bookmarkGroups) == [keptGroup, renamedGroup, deletedGroup]

        // Mutate
        renamedGroup.name = "i have been renamed"

        // Replace state
        userDefaultsStore.replaceBookmarkGroups(with: [keptGroup, renamedGroup, newGroup])

        // Verify new state
        expect(self.userDefaultsStore.bookmarkGroups) == [keptGroup, renamedGroup, newGroup]
        expect(self.userDefaultsStore.findGroup(id: renamedGroup.id)!.name) == "i have been renamed"
        expect(self.userDefaultsStore.findGroup(id: deletedGroup.id)).to(beNil())
    }

    // MARK: - Bookmarks

    func test_bookmarks_retrieval_notInGroup() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)

        let stop = stops[0]

        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark, to: group)

        let bookmark2 = Bookmark(name: "My Bookmark 2", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark2)

        expect(self.userDefaultsStore.bookmarksInGroup(nil)) == [bookmark2]
    }

    func test_bookmarks_retrieval_inGroup() {
        let group = BookmarkGroup(name: "Group!", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)

        let stop = stops[0]

        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark, to: group)

        let bookmark2 = Bookmark(name: "My Bookmark 2", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark2)

        expect(self.userDefaultsStore.bookmarksInGroup(group)) == [bookmark]
    }

    func test_bookmarks_propertyRoundTripping() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        expect(self.userDefaultsStore.bookmarks) == [bookmark]
    }

    func test_bookmark_findByID() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        expect(self.userDefaultsStore.findBookmark(id: bookmark.id)) == bookmark
    }

    func test_bookmark_findByStopID() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        expect(self.userDefaultsStore.findBookmark(stopID: stop.id)) == bookmark
    }

    func test_bookmark_find_noMatch() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        expect(self.userDefaultsStore.findBookmark(id: UUID())).to(beNil())
    }

    func test_bookmark_addToGroup_groupUnregistered() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        let group = BookmarkGroup(name: "My Group", sortOrder: 0)
        userDefaultsStore.add(bookmark, to: group)

        expect(self.userDefaultsStore.bookmarkGroups) == [group]
        expect(self.userDefaultsStore.bookmarks) == [bookmark]
        expect(self.userDefaultsStore.bookmarksInGroup(group)) == [bookmark]
    }

    func test_bookmark_changeGroup() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)

        let group = BookmarkGroup(name: "My Group", sortOrder: 0)
        userDefaultsStore.add(bookmark, to: group)

        let group2 = BookmarkGroup(name: "New Group", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group2)

        userDefaultsStore.add(bookmark, to: group2)

        expect(self.userDefaultsStore.bookmarkGroups) == [group, group2]
        expect(self.userDefaultsStore.bookmarks.first!.id) == bookmark.id
        expect(self.userDefaultsStore.bookmarksInGroup(group)) == []
        expect(self.userDefaultsStore.bookmarksInGroup(group2).first!.id) == bookmark.id
    }

    func test_bookmark_removeFromGroup() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)

        let group = BookmarkGroup(name: "My Group", sortOrder: 0)
        userDefaultsStore.add(bookmark, to: group)

        userDefaultsStore.add(bookmark, to: nil)

        expect(self.userDefaultsStore.bookmarkGroups) == [group]
        expect(self.userDefaultsStore.bookmarks.first!.id) == bookmark.id
        expect(self.userDefaultsStore.bookmarksInGroup(group)) == []
    }

    func test_bookmark_addToGroup_groupRegistered() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        let group = BookmarkGroup(name: "My Group", sortOrder: 0)
        userDefaultsStore.upsert(bookmarkGroup: group)
        userDefaultsStore.add(bookmark, to: group)

        expect(self.userDefaultsStore.bookmarkGroups) == [group]
        expect(self.userDefaultsStore.bookmarks) == [bookmark]
        expect(self.userDefaultsStore.bookmarksInGroup(group)) == [bookmark]
    }

    func test_bookmark_addDuplicate() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)

        userDefaultsStore.add(bookmark)
        userDefaultsStore.add(bookmark)

        expect(self.userDefaultsStore.bookmarks) == [bookmark]
    }

    func test_bookmark_delete() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)

        userDefaultsStore.add(bookmark)
        userDefaultsStore.delete(bookmark: bookmark)

        expect(self.userDefaultsStore.bookmarks) == []
    }

    func test_bookmark_deleteNonexistent() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        let bookmark2 = Bookmark(name: "My Bookmark 2", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)

        userDefaultsStore.add(bookmark)
        userDefaultsStore.delete(bookmark: bookmark2)

        expect(self.userDefaultsStore.bookmarks) == [bookmark]
    }

    func test_bookmark_add_existingRecord() {
        let stop = stops[0]

        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        bookmark.name = "Changed Name"
        userDefaultsStore.add(bookmark)

        expect(self.userDefaultsStore.bookmarks.count) == 1
        expect(self.userDefaultsStore.bookmarks.first!.name) == "Changed Name"
    }
}
