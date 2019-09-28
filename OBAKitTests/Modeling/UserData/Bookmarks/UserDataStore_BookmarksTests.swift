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
        let group = BookmarkGroup(name: "Group!")

        expect(self.userDefaultsStore.bookmarkGroups) == []
        userDefaultsStore.add(bookmarkGroup: group)
        expect(self.userDefaultsStore.bookmarkGroups) == [group]
    }

    func test_bookmarkGroups_addDuplicate() {
        let group = BookmarkGroup(name: "Group!")

        userDefaultsStore.add(bookmarkGroup: group)
        userDefaultsStore.add(bookmarkGroup: group)
        expect(self.userDefaultsStore.bookmarkGroups) == [group]

    }

    func test_bookmarkGroups_delete() {
        let group = BookmarkGroup(name: "Group!")
        userDefaultsStore.add(bookmarkGroup: group)
        userDefaultsStore.delete(bookmarkGroup: group)
        expect(self.userDefaultsStore.bookmarkGroups) == []
    }

    func test_bookmarkGroups_deleteNonexistent() {
        let group = BookmarkGroup(name: "Group!")
        let group2 = BookmarkGroup(name: "Group!")
        userDefaultsStore.add(bookmarkGroup: group)
        userDefaultsStore.delete(bookmarkGroup: group2)
        expect(self.userDefaultsStore.bookmarkGroups) == [group]
    }

    // MARK: - Bookmarks

    func test_bookmarks_retrieval_notInGroup() {
        let group = BookmarkGroup(name: "Group!")
        userDefaultsStore.add(bookmarkGroup: group)

        let stop = stops[0]

        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark, to: group)

        let bookmark2 = Bookmark(name: "My Bookmark 2", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark2)

        expect(self.userDefaultsStore.bookmarksInGroup(nil)) == [bookmark2]
    }

    func test_bookmarks_retrieval_inGroup() {
        let group = BookmarkGroup(name: "Group!")
        userDefaultsStore.add(bookmarkGroup: group)

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

    func test_bookmark_find_match() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        expect(self.userDefaultsStore.findBookmark(uuid: bookmark.uuid)) == bookmark
    }

    func test_bookmark_find_noMatch() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        userDefaultsStore.add(bookmark)
        expect(self.userDefaultsStore.findBookmark(uuid: UUID())).to(beNil())
    }

    func test_bookmark_addToGroup_groupUnregistered() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        let group = BookmarkGroup(name: "My Group")
        userDefaultsStore.add(bookmark, to: group)

        expect(self.userDefaultsStore.bookmarkGroups) == [group]
        expect(self.userDefaultsStore.bookmarks) == [bookmark]
        expect(self.userDefaultsStore.bookmarksInGroup(group)) == [bookmark]
    }

    func test_bookmark_changeGroup() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)

        let group = BookmarkGroup(name: "My Group")
        userDefaultsStore.add(bookmark, to: group)

        let group2 = BookmarkGroup(name: "New Group")
        userDefaultsStore.add(bookmarkGroup: group2)

        userDefaultsStore.add(bookmark, to: group2)

        expect(self.userDefaultsStore.bookmarkGroups) == [group, group2]
        expect(self.userDefaultsStore.bookmarks.first!.uuid) == bookmark.uuid
        expect(self.userDefaultsStore.bookmarksInGroup(group)) == []
        expect(self.userDefaultsStore.bookmarksInGroup(group2).first!.uuid) == bookmark.uuid
    }

    func test_bookmark_removeFromGroup() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)

        let group = BookmarkGroup(name: "My Group")
        userDefaultsStore.add(bookmark, to: group)

        userDefaultsStore.add(bookmark, to: nil)

        expect(self.userDefaultsStore.bookmarkGroups) == [group]
        expect(self.userDefaultsStore.bookmarks.first!.uuid) == bookmark.uuid
        expect(self.userDefaultsStore.bookmarksInGroup(group)) == []
    }

    func test_bookmark_addToGroup_groupRegistered() {
        let stop = stops[0]
        let bookmark = Bookmark(name: "My Bookmark", regionIdentifier: pugetSoundRegion.regionIdentifier, stop: stop)
        let group = BookmarkGroup(name: "My Group")
        userDefaultsStore.add(bookmarkGroup: group)
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
