//
//  WatchBookmarkSyncTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

class WatchBookmarkSyncTests: OBATestCase {

    var region: Region!
    var stops: [Stop]!

    override func setUp() {
        super.setUp()

        region = try! Fixtures.loadSomeRegions()[1]
        stops = try! Fixtures.loadSomeStops()
    }

    func testWatchBookmarkSyncFlow() throws {
        // 1. Create a Bookmark (iOS model)
        let stop = stops[0]
        let bookmark = Bookmark(name: "Test Bookmark", regionIdentifier: region.regionIdentifier, stop: stop)
        
        // 2. Convert to WatchBookmark (shared model)
        let watchBookmark = bookmark.watchBookmarkObject
        
        expect(watchBookmark.id) == bookmark.id
        expect(watchBookmark.stopID) == bookmark.stopID
        expect(watchBookmark.name) == bookmark.name
        expect(watchBookmark.stop?.id) == stop.id
        expect(watchBookmark.stop?.latitude) == stop.location.coordinate.latitude
        expect(watchBookmark.stop?.longitude) == stop.location.coordinate.longitude
        expect(watchBookmark.stop?.locationType) == stop.locationType.rawValue

        // 3. Simulate serialization to a dictionary (like Application.swift does for transferUserInfo)
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(watchBookmark)
        let dictionary = try JSONSerialization.jsonObject(with: encodedData, options: []) as? [String: Any]
        
        expect(dictionary).toNot(beNil())
        
        // 4. Simulate receiving multiple bookmarks in a userInfo payload
        let userInfoPayload = ["bookmarks": [dictionary!]]
        
        // 5. Simulate deserialization from that dictionary back to WatchBookmark (like BookmarksSyncManager does)
        guard let bookmarksFromPayload = userInfoPayload["bookmarks"] as? [[String: Any]] else {
            fail("Payload should contain bookmarks array")
            return
        }
        
        let receivedData = try JSONSerialization.data(withJSONObject: bookmarksFromPayload, options: [])
        let decoder = JSONDecoder()
        let decodedBookmarks = try decoder.decode([WatchBookmark].self, from: receivedData)
        
        expect(decodedBookmarks.count) == 1
        let decodedBookmark = decodedBookmarks[0]
        
        expect(decodedBookmark.id) == watchBookmark.id
        expect(decodedBookmark.stopID) == watchBookmark.stopID
        expect(decodedBookmark.name) == watchBookmark.name
        expect(decodedBookmark.stop?.id) == watchBookmark.stop?.id
        expect(decodedBookmark.stop?.latitude) == watchBookmark.stop?.latitude
        expect(decodedBookmark.stop?.longitude) == watchBookmark.stop?.longitude
        expect(decodedBookmark.stop?.locationType) == watchBookmark.stop?.locationType
    }
}
