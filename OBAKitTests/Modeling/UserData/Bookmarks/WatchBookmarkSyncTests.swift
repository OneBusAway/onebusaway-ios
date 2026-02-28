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

    // MARK: - Sync Manager Update/Retrieve Pipeline Tests
    //
    // BookmarksSyncManager.updateBookmarks() receives [[String: Any]] over WatchConnectivity,
    // deserializes it via JSONSerialization → JSONDecoder → [WatchBookmark], re-encodes to Data,
    // and persists it via UserDefaults. getBookmarks() reverses the process.
    // These tests verify the full round-trip without requiring access to the Watch app target.

    /// Helper: emulates the BookmarksSyncManager.updateBookmarks pipeline and returns the
    /// persisted Data, so the retrieve path can be tested in isolation.
    private func encodeBookmarkPayload(_ bookmarks: [WatchBookmark]) throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(bookmarks)
        // Simulate the wire format: encode → serialize to [[String:Any]] → deserialize → re-encode
        let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let wireData = try JSONSerialization.data(withJSONObject: array)
        let decoded = try JSONDecoder().decode([WatchBookmark].self, from: wireData)
        return try JSONEncoder().encode(decoded)
    }

    func testSyncManagerUpdateBookmarks_singleBookmark() throws {
        let stop = stops[0]
        let bookmark = Bookmark(name: "Downtown Stop", regionIdentifier: region.regionIdentifier, stop: stop)
        let watchBookmark = bookmark.watchBookmarkObject

        let persistedData = try encodeBookmarkPayload([watchBookmark])
        let retrieved = try JSONDecoder().decode([WatchBookmark].self, from: persistedData)

        expect(retrieved.count) == 1
        expect(retrieved[0].id) == watchBookmark.id
        expect(retrieved[0].stopID) == watchBookmark.stopID
        expect(retrieved[0].name) == watchBookmark.name
        expect(retrieved[0].stop?.latitude) == watchBookmark.stop?.latitude
        expect(retrieved[0].stop?.longitude) == watchBookmark.stop?.longitude
    }

    func testSyncManagerUpdateBookmarks_multipleBookmarks() throws {
        let bookmarks: [WatchBookmark] = stops.prefix(3).map { stop in
            let b = Bookmark(name: stop.name, regionIdentifier: region.regionIdentifier, stop: stop)
            return b.watchBookmarkObject
        }

        let persistedData = try encodeBookmarkPayload(bookmarks)
        let retrieved = try JSONDecoder().decode([WatchBookmark].self, from: persistedData)

        expect(retrieved.count) == bookmarks.count
        for (original, decoded) in zip(bookmarks, retrieved) {
            expect(decoded.id) == original.id
            expect(decoded.stopID) == original.stopID
            expect(decoded.name) == original.name
        }
    }

    func testSyncManagerUpdateBookmarks_emptyArray() throws {
        let persistedData = try encodeBookmarkPayload([])
        let retrieved = try JSONDecoder().decode([WatchBookmark].self, from: persistedData)
        expect(retrieved).to(beEmpty(), description: "Empty payload must persist and retrieve as empty array")
    }

    func testSyncManagerBookmark_stopWithAllOptionalFields() throws {
        // Create an OBAStop with every optional field populated.
        let fullStop = OBAStop(
            id: "FULL-001",
            name: "Full Featured Stop",
            latitude: 47.6062,
            longitude: -122.3321,
            code: "F001",
            direction: "N",
            routeNames: "10, 12, 44",
            locationType: 1
        )
        let watchBookmark = WatchBookmark(
            id: UUID(),
            stopID: fullStop.id,
            name: fullStop.name,
            routeShortName: "10",
            tripHeadsign: "Downtown",
            stop: fullStop
        )

        let persistedData = try encodeBookmarkPayload([watchBookmark])
        let retrieved = try JSONDecoder().decode([WatchBookmark].self, from: persistedData)

        let decoded = try XCTUnwrap(retrieved.first)
        expect(decoded.stop?.code) == "F001"
        expect(decoded.stop?.direction) == "N"
        expect(decoded.stop?.routeNames) == "10, 12, 44"
        expect(decoded.stop?.locationType) == 1
        expect(decoded.routeShortName) == "10"
        expect(decoded.tripHeadsign) == "Downtown"
    }

    func testSyncManagerWatchAlarmItem_codableRoundTrip() throws {
        // WatchAlarmItem mirrors AlarmsSyncManager's wire format.
        let alarm = WatchAlarmItem(
            id: "alarm-001",
            stopID: "STOP-99",
            routeShortName: "B",
            headsign: "Airport",
            scheduledTime: Date(timeIntervalSince1970: 1_710_000_000),
            status: "active"
        )

        let encoded = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(WatchAlarmItem.self, from: encoded)

        expect(decoded.id) == alarm.id
        expect(decoded.stopID) == alarm.stopID
        expect(decoded.routeShortName) == alarm.routeShortName
        expect(decoded.headsign) == alarm.headsign
        expect(decoded.status) == alarm.status
        // scheduledTime uses default .secondsSince1970 encoder — allow 1-second tolerance.
        expect(decoded.scheduledTime?.timeIntervalSince1970) ≈ (alarm.scheduledTime!.timeIntervalSince1970, delta: 1)
    }
}
